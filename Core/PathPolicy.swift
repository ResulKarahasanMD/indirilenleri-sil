import Foundation

/// Decides which paths the engine may touch at all. Only user-visible iCloud Drive locations are allowed;
/// the rest of ~/Library/Mobile Documents is app-private data and stays off limits.
struct PathPolicy: Sendable {
    let home: String
    /// Turns a path into its real, symlink-free form; nil when it does not exist.
    let resolve: @Sendable (String) -> String?

    init(home: String = PathPolicy.userHome(), resolve: @escaping @Sendable (String) -> String? = PathPolicy.realpathResolve) {
        self.home = resolve(home) ?? home
        self.resolve = resolve
    }

    var mobileDocuments: String { home + "/Library/Mobile Documents" }
    var cloudDocs: String { mobileDocuments + "/com~apple~CloudDocs" }
    var desktop: String { home + "/Desktop" }
    var documents: String { home + "/Documents" }

    /// The allowed root that `path` (already resolved) lies in or equals; nil when outside every root.
    func root(containing path: String) -> String? {
        for root in [cloudDocs, desktop, documents] where path == root || path.hasPrefix(root + "/") { return root }
        guard let container = container(of: path), container != "com~apple~CloudDocs" else { return nil }
        let root = mobileDocuments + "/" + container + "/Documents"
        return (path == root || path.hasPrefix(root + "/")) ? root : nil
    }

    /// Where a path lies, in words that are safe to log: never a file or folder name.
    enum Location: String, Sendable {
        case iCloudDrive = "iCloud Drive"
        case desktop = "Masaüstü"
        case documents = "Belgeler"
        case appFolder = "uygulama klasörü"
        case outside = "izinli konum dışı"
    }

    func location(of path: String) -> Location {
        switch root(containing: path) {
        case nil: .outside
        case cloudDocs: .iCloudDrive
        case desktop: .desktop
        case documents: .documents
        default: .appFolder
        }
    }

    /// The folders the Finder extension asks Finder to show its menu and toolbar item in. Mobile
    /// Documents as a whole, because every app folder under it is an allowed root.
    var finderSyncDirectories: [String] { [mobileDocuments, desktop, documents] }

    /// App containers whose app keeps its own documents downloaded, so evicting only causes a
    /// re-download. Matched by suffix so a changed team-ID prefix still matches.
    /// Notability: 3 of 4 evicted notes came back within ~1 min with Finder's preview closed (2026-09-27).
    static let selfDownloadingContainers = ["com~gingerlabs~Notability"]

    func isSelfDownloadingContainer(_ path: String) -> Bool {
        guard let container = container(of: path) else { return false }
        return Self.selfDownloadingContainers.contains { container.hasSuffix($0) }
    }

    /// Name of the iCloud container folder a path under Mobile Documents belongs to.
    private func container(of path: String) -> Substring? {
        let prefix = mobileDocuments + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return path.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).first
    }

    // MARK: - Name rules

    /// Files never counted or touched: Finder metadata and legacy placeholders (removing a
    /// `.name.icloud` placeholder would delete the cloud copy, so the engine must not even look).
    static func isIgnoredName(_ name: String) -> Bool {
        name == ".DS_Store" || name == "Icon\r" || (name.hasPrefix(".") && name.hasSuffix(".icloud"))
    }

    static func isIgnoredDirectory(_ name: String) -> Bool {
        [".Trash", ".Trashes", ".DocumentRevisions-V100", ".fseventsd", ".Spotlight-V100"].contains(name)
    }

    /// Bundles whose parts are live databases or executables; left downloaded as a whole.
    static let excludedPackageExtensions: Set<String> = ["app", "photoslibrary", "fcpbundle", "logicx", "musiclibrary", "tvlibrary"]

    static func isExcludedPackage(_ name: String) -> Bool {
        excludedPackageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    // MARK: - Environment

    /// Real home even inside an App Sandbox, where NSHomeDirectory() returns the container.
    static func userHome() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    @Sendable static func realpathResolve(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}
