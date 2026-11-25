import Foundation
import Darwin
import Synchronization

/// st_flags bit set on files and folders whose content lives only in the cloud (sys/stat.h SF_DATALESS).
let SFDatalessFlag: UInt32 = 0x4000_0000

/// What is on disk at a path, found out without ever downloading anything.
enum LocalState: Equatable, Sendable {
    case missing
    /// The content lives only in iCloud.
    case dataless
    /// Bytes allocated on disk: the file itself, or everything local inside a package.
    case local(bytes: Int64)
}

/// Everything the engine needs to know about, or do to, a file. The live adapter talks to iCloud
/// and the file system; the tests put an in-memory one in its place.
struct CloudFiles: Sendable {
    /// iCloud state of an item that is on disk. Throws when it cannot be read.
    var state: @Sendable (_ path: String) throws -> ItemState
    /// Whether an entry the walk is looking at is cloud-only; `flags` are its st_flags.
    var isDataless: @Sendable (_ path: String, _ flags: UInt32) -> Bool
    var isPackage: @Sendable (_ path: String) -> Bool
    var localState: @Sendable (_ path: String) -> LocalState
    /// Asks iCloud to remove the local copy. Returns before the data is gone.
    var evict: @Sendable (_ path: String) throws -> Void
    var freeSpace: @Sendable () -> VolumeSpace
}

extension CloudFiles {
    /// With this policy any access to a dataless file or folder fails (EDEADLK) instead of
    /// downloading it, so neither scanning nor evicting can pull data from iCloud.
    static func preventDownloads() -> Bool {
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS,
                       IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0
    }

    static func live(home: String = PathPolicy.userHome()) -> CloudFiles {
        let pins = PinCache()
        return CloudFiles(
            state: { path in try liveState(path, pins: pins, home: home) },
            isDataless: { _, flags in flags & SFDatalessFlag != 0 },
            isPackage: { path in
                let values = try? URL(fileURLWithPath: path, isDirectory: true).resourceValues(forKeys: [.isPackageKey])
                return values?.isPackage ?? false
            },
            localState: liveLocalState,
            evict: { path in try FileManager.default.evictUbiquitousItem(at: URL(fileURLWithPath: path)) },
            freeSpace: { liveFreeSpace(home: home) })
    }

    private static let stateKeys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemIsDownloadingKey,
        .ubiquitousItemHasUnresolvedConflictsKey, .ubiquitousItemIsExcludedFromSyncKey,
        .contentModificationDateKey, .attributeModificationDateKey,
    ]

    private static func liveState(_ path: String, pins: PinCache, home: String) throws -> ItemState {
        var url = URL(fileURLWithPath: path)
        url.removeAllCachedResourceValues()
        let values = try url.resourceValues(forKeys: stateKeys)
        var state = ItemState()
        state.isDataless = liveLocalState(path) == .dataless
        state.isUbiquitous = values.isUbiquitousItem ?? false
        state.download = switch values.ubiquitousItemDownloadingStatus {
        case .some(.notDownloaded): .notDownloaded
        case .some(.downloaded): .downloaded
        case .some(.current): .current
        default: .unknown
        }
        state.isUploaded = values.ubiquitousItemIsUploaded ?? false
        state.isUploading = values.ubiquitousItemIsUploading ?? false
        state.isDownloading = values.ubiquitousItemIsDownloading ?? false
        state.hasConflicts = values.ubiquitousItemHasUnresolvedConflicts ?? false
        state.isExcludedFromSync = values.ubiquitousItemIsExcludedFromSync ?? false
        state.modified = values.contentModificationDate
        state.changed = values.attributeModificationDate
        state.isPinned = pins.isPinned(path, inside: home)
        return state
    }

    @Sendable static func liveLocalState(_ path: String) -> LocalState {
        var status = stat()
        guard lstat(path, &status) == 0 else { return .missing }
        if status.st_flags & SFDatalessFlag != 0 { return .dataless }
        guard status.st_mode & S_IFMT == S_IFDIR else { return .local(bytes: Int64(status.st_blocks) * 512) }
        var total: Int64 = 0
        Walk.visit(path) { entry in
            switch entry {
            case .folder(_, let status, _):
                return status.st_flags & SFDatalessFlag != 0 ? .prune : .proceed
            case .file(_, let status):
                total += Int64(status.st_blocks) * 512
                return .proceed
            case .unreadable:
                return .proceed
            }
        }
        return .local(bytes: total)
    }

    private static func liveFreeSpace(home: String) -> VolumeSpace {
        let url = URL(fileURLWithPath: home, isDirectory: true)
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        else { return VolumeSpace() }
        return VolumeSpace(available: Int64(values.volumeAvailableCapacity ?? -1),
                           important: values.volumeAvailableCapacityForImportantUsage ?? -1)
    }
}

/// Depth-first walk over real files. It never follows symlinks, never leaves the volume, and asks
/// the visitor about a folder before listing it, so a folder can be pruned unopened.
enum Walk {
    enum Entry {
        case folder(path: String, status: stat, depth: Int)
        case file(path: String, status: stat)
        case unreadable(path: String, code: Int32)
    }

    enum Step { case proceed, prune, stop }

    /// Returns the errno of a root that could not be opened, 0 otherwise.
    @discardableResult
    static func visit(_ root: String, _ visitor: (Entry) -> Step) -> Int32 {
        guard let start = strdup(root) else { return ENOMEM }
        defer { free(start) }
        var roots: [UnsafeMutablePointer<CChar>?] = [start, nil]
        guard let stream = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return errno }
        defer { fts_close(stream) }

        while let next = fts_read(stream) {
            let found = next.pointee
            let path = String(cString: found.fts_path)
            let entry: Entry
            switch Int32(found.fts_info) {
            case FTS_D:
                guard let status = found.fts_statp?.pointee else { continue }
                entry = .folder(path: path, status: status, depth: Int(found.fts_level))
            case FTS_F:
                guard let status = found.fts_statp?.pointee else { continue }
                entry = .file(path: path, status: status)
            case FTS_DNR, FTS_ERR, FTS_NS:
                entry = .unreadable(path: path, code: found.fts_errno)
            default:
                continue // folders on the way back up, symlinks, cycles
            }
            switch visitor(entry) {
            case .proceed: break
            case .prune: fts_set(stream, next, FTS_SKIP)
            case .stop: return 0
            }
        }
        return 0
    }
}

/// Remembers which folders carry the "Keep Downloaded" marker, so a scan reads each folder once.
final class PinCache: Sendable {
    /// Undocumented FileProvider marker, observed 2026-09-27 on macOS 26.6.2: present on an item with
    /// "İndirileni Tut" (fileproviderctl: isKeepDownloaded = 1), absent on unpinned siblings.
    /// Used only to skip; if a future macOS drops it, `--verify` still reports re-downloads.
    static let marker = "com.apple.fileprovider.pinned#PX"

    private let folders = Mutex<[String: Bool]>([:])

    static func hasMarker(_ path: String) -> Bool {
        getxattr(path, marker, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// The item itself, or a folder above it below `boundary`, carries the marker.
    func isPinned(_ path: String, inside boundary: String) -> Bool {
        if Self.hasMarker(path) { return true }
        var folder = (path as NSString).deletingLastPathComponent
        var walked: [String] = []
        var pinned = false
        while folder.hasPrefix(boundary + "/") {
            if let known = folders.withLock({ $0[folder] }) { pinned = known; break }
            walked.append(folder)
            if Self.hasMarker(folder) { pinned = true; break }
            folder = (folder as NSString).deletingLastPathComponent
        }
        // Every folder walked shares the answer of the first pinned (or known) folder above it.
        folders.withLock { known in for folder in walked { known[folder] = pinned } }
        return pinned
    }
}
