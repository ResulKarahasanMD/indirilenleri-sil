import Foundation

/// Scans selected paths and evicts ("Remove Download") local copies of iCloud items that are
/// fully uploaded. It never writes, moves or deletes anything and never triggers a download.
struct EvictEngine: Sendable {
    struct Hooks: Sendable {
        var isCancelled: @Sendable () -> Bool = { false }
        var progress: @Sendable (Progress) -> Void = { _ in }
    }

    /// Eviction requests sent in parallel. fileproviderd works through them one by one anyway.
    static let workers = 3

    let policy: PathPolicy
    let files: CloudFiles
    let hooks: Hooks
    /// Waiting for confirmation ends after this long without any item settling.
    var stallTimeout: TimeInterval = 20
    var pollInterval: TimeInterval = 0.5
    var lockURL = RunLog.defaultDirectory().appendingPathComponent(".evict.lock")

    init(policy: PathPolicy = PathPolicy(), files: CloudFiles? = nil, hooks: Hooks = Hooks()) {
        self.policy = policy
        self.files = files ?? .live(home: policy.home)
        self.hooks = hooks
    }

    // MARK: - Scan

    func scan(_ paths: [String], now: Date = Date()) -> ScanResult {
        var result = ScanResult()
        var visited = Set<FileID>()
        var inputs = Set<String>()
        for raw in paths {
            if hooks.isCancelled() { break }
            guard let path = policy.resolve(raw) else {
                result.addError(raw, String(cString: strerror(errno)))
                continue
            }
            guard let root = policy.root(containing: path) else {
                result.skip(.outsideRoots, path: path, bytes: 0)
                continue
            }
            if policy.isSelfDownloadingContainer(path) {
                // Not walked at all: only the local bytes it keeps are reported.
                result.skip(.selfDownloadingApp, path: path, bytes: localBytes(path))
                continue
            }
            // A selection inside a package stands for the package: iCloud keeps, evicts and
            // excludes packages as a whole, and so does the walk when it meets one.
            let input = enclosingPackage(of: path, below: root) ?? path
            guard inputs.insert(input).inserted else { continue }
            result.addInput(input)
            walk(input, into: &result, visited: &visited, now: now)
        }
        return result
    }

    /// The outermost package between `root` and `path` that contains `path`.
    private func enclosingPackage(of path: String, below root: String) -> String? {
        var folder = root
        for name in path.dropFirst(root.count).split(separator: "/").dropLast() {
            folder += "/" + name
            if PathPolicy.isExcludedPackage(String(name)) || files.isPackage(folder) { return folder }
        }
        return nil
    }

    private struct FileID: Hashable {
        let device: Int32
        let inode: UInt64
        init(_ status: stat) { device = status.st_dev; inode = status.st_ino }
    }

    private func walk(_ root: String, into result: inout ScanResult, visited: inout Set<FileID>, now: Date) {
        let failure = Walk.visit(root) { entry in
            if hooks.isCancelled() { return .stop }
            switch entry {
            case .folder(let path, let status, let depth):
                let name = (path as NSString).lastPathComponent
                guard visited.insert(FileID(status)).inserted,
                      !(depth > 0 && PathPolicy.isIgnoredDirectory(name)) else { return .prune }
                if files.isDataless(path, status.st_flags) {
                    // Listing it would download the folder; nothing local inside anyway.
                    result.addCloudOnlyFolder(path)
                    return .prune
                }
                if PathPolicy.isExcludedPackage(name) {
                    result.skip(.excludedPackage, path: path, bytes: localBytes(path))
                    return .prune
                }
                guard files.isPackage(path) else { return .proceed }
                classify(path, isPackage: true, bytes: localBytes(path), into: &result, now: now)
                return .prune

            case .file(let path, let status):
                let name = (path as NSString).lastPathComponent
                guard !PathPolicy.isIgnoredName(name), visited.insert(FileID(status)).inserted else { return .proceed }
                if files.isDataless(path, status.st_flags) {
                    result.sawItem()
                    result.skip(.alreadyEvicted, path: path, bytes: 0)
                } else {
                    classify(path, isPackage: false, bytes: Int64(status.st_blocks) * 512, into: &result, now: now)
                }
                return .proceed

            case .unreadable(let path, let code):
                if code == EDEADLK {
                    result.addCloudOnlyFolder(path)
                } else {
                    result.addError(path, String(cString: strerror(code)))
                }
                return .proceed
            }
        }
        if failure != 0 { result.addError(root, String(cString: strerror(failure))) }
    }

    private func classify(_ path: String, isPackage: Bool, bytes: Int64, into result: inout ScanResult, now: Date) {
        result.sawItem()
        do {
            switch Eligibility.decide(try files.state(path), localBytes: bytes, now: now) {
            case .evict: result.addCandidate(Candidate(path: path, bytes: bytes, isPackage: isPackage))
            case .skip(let reason): result.skip(reason, path: path, bytes: bytes)
            }
        } catch {
            // Not "outside iCloud": a permission problem must not look like there is nothing to do.
            result.addError(path, ProviderError.describe(error))
        }
        if result.itemsSeen % 250 == 0 {
            hooks.progress(.scanning(items: result.itemsSeen, evictableBytes: result.candidateBytes))
        }
    }

    func localBytes(_ path: String) -> Int64 {
        if case .local(let bytes) = files.localState(path) { return bytes }
        return 0
    }
}
