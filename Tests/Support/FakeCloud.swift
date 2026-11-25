import Foundation
import Synchronization

/// In-memory stand-in for iCloud. The files are real (a `TempHome`); what iCloud says about them
/// and what an eviction request does to them is scripted here.
final class FakeCloud: Sendable {
    enum AfterEvict: Sendable {
        /// The data leaves the disk (after `pollsToSettle` looks).
        case settles
        /// The item is gone when looked at again: moved or deleted meanwhile.
        case vanishes
        /// The request is accepted, the data never leaves.
        case staysLocal
    }

    struct Script: Sendable {
        /// What iCloud reports for a path. Every other path is a fully uploaded, old file.
        var states: [String: ItemState] = [:]
        /// Paths whose state cannot be read.
        var unreadable: Set<String> = []
        /// Files and folders that exist only in the cloud.
        var dataless: Set<String> = []
        var packageExtensions: Set<String> = ["rtfd", "pages"]
        /// What the provider answers an eviction request with instead of accepting it.
        var refusals: [String: NSError] = [:]
        var afterEvict: [String: AfterEvict] = [:]
        /// Looks at an evicted item before it reports being cloud-only.
        var pollsToSettle = 0
    }

    /// A file iCloud has fully uploaded and that was last touched years ago.
    static let uploaded = ItemState(isUbiquitous: true, download: .current, isUploaded: true,
                                    modified: Date(timeIntervalSince1970: 1_500_000_000),
                                    changed: Date(timeIntervalSince1970: 1_500_000_000))

    private struct Memory: Sendable {
        var script: Script
        var evicted: [String] = []
        var stateReads: [String] = []
        var polls: [String: Int] = [:]
    }

    private let memory: Mutex<Memory>

    init(_ script: Script = Script()) {
        memory = Mutex(Memory(script: script))
    }

    /// Eviction requests the provider accepted, in order.
    var evicted: [String] { memory.withLock { $0.evicted } }
    /// Paths whose iCloud state was asked for.
    var stateReads: [String] { memory.withLock { $0.stateReads } }

    /// Changes the script while a run is under way.
    func rescript(_ change: @Sendable (inout Script) -> Void) {
        memory.withLock { change(&$0.script) }
    }

    var files: CloudFiles {
        CloudFiles(
            state: { [self] path in
                try memory.withLock { memory in
                    memory.stateReads.append(path)
                    if memory.script.unreadable.contains(path) {
                        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
                    }
                    return memory.script.states[path] ?? Self.uploaded
                }
            },
            isDataless: { [self] path, flags in
                flags & SFDatalessFlag != 0 || memory.withLock { $0.script.dataless.contains(path) }
            },
            isPackage: { [self] path in
                let ext = (path as NSString).pathExtension.lowercased()
                return memory.withLock { $0.script.packageExtensions.contains(ext) }
            },
            localState: { [self] path in
                let scripted: LocalState? = memory.withLock { memory in
                    if memory.script.dataless.contains(path) { return .dataless }
                    guard memory.evicted.contains(path) else { return nil }
                    switch memory.script.afterEvict[path] ?? .settles {
                    case .vanishes: return .missing
                    case .staysLocal: return nil
                    case .settles:
                        memory.polls[path, default: 0] += 1
                        return memory.polls[path, default: 0] > memory.script.pollsToSettle ? .dataless : nil
                    }
                }
                return scripted ?? CloudFiles.liveLocalState(path)
            },
            evict: { [self] path in
                try memory.withLock { memory in
                    if let refusal = memory.script.refusals[path] { throw refusal }
                    memory.evicted.append(path)
                }
            },
            freeSpace: { VolumeSpace() })
    }
}
