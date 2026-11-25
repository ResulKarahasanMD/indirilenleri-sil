import Foundation

struct Tally: Equatable, Sendable {
    var count = 0
    var bytes: Int64 = 0
    mutating func add(_ b: Int64) { count += 1; bytes += b }
}

/// A file or package whose local copy can be evicted.
struct Candidate: Equatable, Sendable {
    let path: String
    let bytes: Int64
    let isPackage: Bool
}

struct SkippedItem: Equatable, Sendable {
    let reason: SkipReason
    let path: String
    let bytes: Int64
}

struct SizedPath: Equatable, Sendable {
    let path: String
    let bytes: Int64
}

struct PathIssue: Equatable, Sendable {
    let path: String
    let message: String
}

struct VolumeSpace: Equatable, Sendable {
    var available: Int64 = -1
    /// Counts purgeable data (e.g. downloaded iCloud files under Optimize Storage) as free.
    var important: Int64 = -1
}

struct ScanResult: Equatable, Sendable {
    /// Path lists kept for the log and `--list` stop growing here; the tallies keep counting.
    static let listLimit = 5000

    /// What was scanned, symlinks resolved.
    private(set) var inputs: [String] = []
    private(set) var candidates: [Candidate] = []
    private(set) var candidateBytes: Int64 = 0
    private(set) var skips: [SkipReason: Tally] = [:]
    /// The items behind `skips`, except those already in the cloud, which are only counted.
    private(set) var skipped: [SkippedItem] = []
    /// Folders whose content lives only in iCloud; never listed, so never downloaded.
    private(set) var cloudOnlyFolders = 0
    private(set) var cloudOnlyFolderPaths: [String] = []
    private(set) var errors: [PathIssue] = []
    /// Files and packages looked at.
    private(set) var itemsSeen = 0

    mutating func addInput(_ path: String) { inputs.append(path) }
    mutating func sawItem() { itemsSeen += 1 }
    mutating func addCloudOnlyFolder(_ path: String) {
        cloudOnlyFolders += 1
        if cloudOnlyFolderPaths.count < Self.listLimit { cloudOnlyFolderPaths.append(path) }
    }
    mutating func addError(_ path: String, _ message: String) { errors.append(PathIssue(path: path, message: message)) }

    mutating func addCandidate(_ candidate: Candidate) {
        candidates.append(candidate)
        candidateBytes += candidate.bytes
    }

    mutating func skip(_ reason: SkipReason, path: String, bytes: Int64) {
        skips[reason, default: Tally()].add(bytes)
        if reason != .alreadyEvicted, skipped.count < Self.listLimit {
            skipped.append(SkippedItem(reason: reason, path: path, bytes: bytes))
        }
    }
}

struct EvictResult: Equatable, Sendable {
    /// Confirmed: the data is gone from disk.
    var evicted = Tally()
    /// The request went through, yet the data was still on disk when waiting stopped.
    var stillLocal = Tally()
    /// Stopped by the user while waiting: requested, outcome unknown.
    var unconfirmed = Tally()
    /// Moved or deleted while the run was under way.
    var missing = Tally()
    /// Skipped at the last moment: the item no longer was what the scan saw.
    var changed: [SkipReason: Tally] = [:]
    /// iCloud turned the request down.
    var refused: [SkipReason: Tally] = [:]
    var errors: [PathIssue] = []
    var cancelled = false
    /// Why the run could not be logged, or not to the end; nil when the log is complete.
    var logFailure: String?
    var spaceBefore = VolumeSpace()
    var spaceAfter = VolumeSpace()
    var requestSeconds = 0.0
    var confirmSeconds = 0.0

    /// Every one of `candidates` items ended up cloud-only.
    func isComplete(of candidates: Int) -> Bool {
        !cancelled && errors.isEmpty && evicted.count == candidates
    }
}

struct VerifyResult: Equatable, Sendable {
    var stillEvicted = 0
    var redownloaded: [SizedPath] = []
    var missing = 0
}

/// What the engine is doing, for whoever shows it.
enum Progress: Equatable, Sendable {
    case scanning(items: Int, evictableBytes: Int64)
    case waitingForOtherRun
    case requesting(done: Int, total: Int)
    case confirming(done: Int, total: Int, freedBytes: Int64)

    /// How far an eviction has come, 0…1; nil while there is nothing to measure. Sending the
    /// requests is the first half, seeing the data leave the disk the second, so the value never
    /// falls from one report to the next.
    var fraction: Double? {
        switch self {
        case .scanning, .waitingForOtherRun: nil
        case .requesting(_, total: 0), .confirming(_, total: 0, _): nil
        case .requesting(let done, let total): 0.5 * Double(done) / Double(total)
        case .confirming(let done, let total, _): 0.5 + 0.5 * Double(done) / Double(total)
        }
    }
}
