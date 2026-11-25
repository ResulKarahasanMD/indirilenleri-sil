import Foundation
import Synchronization

extension EvictEngine {
    /// What became of one candidate when its turn came.
    private enum Outcome: Sendable {
        case requested(SizedPath)
        case missing(bytes: Int64)
        case changed(SkipReason, bytes: Int64)
        case refused(SkipReason, bytes: Int64)
        case failed(PathIssue)
    }

    private struct Requests: Sendable {
        var requested: [SizedPath] = []
        var missing = Tally()
        var changed: [SkipReason: Tally] = [:]
        var refused: [SkipReason: Tally] = [:]
        var errors: [PathIssue] = []
        var done = 0

        mutating func record(_ outcome: Outcome) {
            done += 1
            switch outcome {
            case .requested(let item): requested.append(item)
            case .missing(let bytes): missing.add(bytes)
            case .changed(let reason, let bytes): changed[reason, default: Tally()].add(bytes)
            case .refused(let reason, let bytes): refused[reason, default: Tally()].add(bytes)
            case .failed(let issue): errors.append(issue)
            }
        }
    }

    /// Evicts what `scan` found and keeps a record of the run in `logDirectory`. The record is best
    /// effort: a full disk is exactly when this tool is needed, so a log that cannot be written
    /// is reported in the result and never stops the run.
    func run(_ scan: ScanResult, logDirectory: URL = RunLog.defaultDirectory()) -> (result: EvictResult, log: URL?) {
        var failure: String?
        var log: RunLog?
        do {
            log = try RunLog(directory: logDirectory, id: RunLog.newID())
        } catch {
            failure = (error as NSError).localizedDescription
        }
        log?.record(scan)
        var result = evict(scan.candidates, log: log)
        result.logFailure = failure ?? log?.failure
        return (result, log?.url)
    }

    func evict(_ candidates: [Candidate], log: RunLog? = nil) -> EvictResult {
        var result = EvictResult()
        // Two runs evicting the same tree make fileproviderd reject requests ("Dosya kilitlenemedi"):
        // one run at a time. The second one looks at every item again when its turn comes.
        guard let lock = RunLock.acquire(at: lockURL, poll: pollInterval, isCancelled: hooks.isCancelled,
                                         onWait: { hooks.progress(.waitingForOtherRun) }) else {
            result.cancelled = true
            return result
        }
        defer { lock.release() }

        result.spaceBefore = files.freeSpace()
        let total = candidates.count
        let workers = max(1, min(Self.workers, total))
        let requests = Mutex(Requests())
        let started = Date()

        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for index in stride(from: worker, to: total, by: workers) {
                if hooks.isCancelled() { break }
                let outcome = request(candidates[index], log: log)
                // Reported under the lock, so reports leave in the order they were counted.
                requests.withLock { requests in
                    requests.record(outcome)
                    if requests.done % 50 == 0 { hooks.progress(.requesting(done: requests.done, total: total)) }
                }
            }
        }
        let sent = requests.withLock { $0 }
        result.missing = sent.missing
        result.changed = sent.changed
        result.refused = sent.refused
        result.errors = sent.errors
        result.requestSeconds = Date().timeIntervalSince(started)

        // Eviction is asynchronous (measured: ~5 s after the calls for a handful of files). An item
        // counts only once its data has left the disk; waiting goes on while fileproviderd keeps
        // making progress and ends after `stallTimeout` without any, or when the user stops it.
        let confirming = Date()
        var pending = sent.requested
        var lastProgress = Date()
        while !pending.isEmpty, !hooks.isCancelled(), Date().timeIntervalSince(lastProgress) < stallTimeout {
            let before = pending.count
            pending.removeAll { item in
                switch Self.settled(files.localState(item.path), before: item.bytes) {
                case .evicted:
                    result.evicted.add(item.bytes)
                    log?.write(.evicted, bytes: item.bytes, path: item.path)
                case .missing:
                    result.missing.add(item.bytes)
                    log?.write(.missing, bytes: item.bytes, path: item.path)
                case nil:
                    return false
                }
                return true
            }
            if pending.count < before { lastProgress = Date() }
            hooks.progress(.confirming(done: sent.done - pending.count, total: total, freedBytes: result.evicted.bytes))
            if !pending.isEmpty { Thread.sleep(forTimeInterval: pollInterval) }
        }
        result.cancelled = hooks.isCancelled()
        for item in pending {
            if result.cancelled {
                result.unconfirmed.add(item.bytes)
                log?.write(.unconfirmed, bytes: item.bytes, path: item.path)
            } else {
                result.stillLocal.add(item.bytes)
                log?.write(.stillLocal, bytes: item.bytes, path: item.path)
            }
        }
        hooks.progress(.confirming(done: sent.done - pending.count, total: total, freedBytes: result.evicted.bytes))
        result.confirmSeconds = Date().timeIntervalSince(confirming)
        result.spaceAfter = files.freeSpace()
        return result
    }

    private func request(_ candidate: Candidate, log: RunLog?) -> Outcome {
        // Look again right before acting: the scan may be minutes old.
        let bytes: Int64
        switch files.localState(candidate.path) {
        case .missing:
            log?.write(.missing, bytes: candidate.bytes, path: candidate.path)
            return .missing(bytes: candidate.bytes)
        case .dataless:
            return skipped(candidate, .alreadyEvicted, log: log)
        case .local(let local):
            bytes = local
        }

        let decision: Decision
        do {
            decision = Eligibility.decide(try files.state(candidate.path), localBytes: bytes, now: Date())
        } catch {
            return failed(candidate, error, bytes: bytes, log: log)
        }
        if case .skip(let reason) = decision { return skipped(candidate, reason, log: log) }

        do {
            try files.evict(candidate.path)
            return .requested(SizedPath(path: candidate.path, bytes: bytes))
        } catch {
            guard let reason = ProviderError.refusal(error) else { return failed(candidate, error, bytes: bytes, log: log) }
            log?.write(.refused, reason: reason.rawValue, bytes: bytes, path: candidate.path)
            return .refused(reason, bytes: bytes)
        }
    }

    private func skipped(_ candidate: Candidate, _ reason: SkipReason, log: RunLog?) -> Outcome {
        log?.write(.skip, reason: reason.rawValue, bytes: candidate.bytes, path: candidate.path)
        return .changed(reason, bytes: candidate.bytes)
    }

    private func failed(_ candidate: Candidate, _ error: Error, bytes: Int64, log: RunLog?) -> Outcome {
        let message = ProviderError.describe(error)
        log?.write(.error, reason: message, bytes: bytes, path: candidate.path)
        return .failed(PathIssue(path: candidate.path, message: message))
    }

    private enum Settled { case evicted, missing }

    /// What a requested item has become: evicted, gone, or (nil) still on disk. An item that
    /// vanished was moved or deleted, not evicted, and nothing was freed by this run.
    private static func settled(_ state: LocalState, before: Int64) -> Settled? {
        switch state {
        case .missing: .missing
        case .dataless: .evicted
        case .local(let bytes): bytes == 0 && before > 0 ? .evicted : nil
        }
    }

    // MARK: - Verify

    /// Re-checks the items a run evicted: are they still cloud-only?
    func verify(_ rows: [RunLog.Row]) -> VerifyResult {
        var result = VerifyResult()
        for row in rows where row.action == RunLog.Action.evicted.rawValue {
            switch files.localState(row.path) {
            case .missing: result.missing += 1
            case .dataless, .local(bytes: 0): result.stillEvicted += 1
            case .local(let bytes): result.redownloaded.append(SizedPath(path: row.path, bytes: bytes))
            }
        }
        return result
    }
}

/// One evicting run at a time, shared by the app and the command line through a lock file.
struct RunLock {
    /// -1 when the lock file cannot be used: the run goes on unlocked.
    private let descriptor: Int32

    /// Waits for the lock, looking every `poll` seconds. Returns nil when cancelled while waiting.
    static func acquire(at url: URL, poll: TimeInterval, isCancelled: () -> Bool, onWait: () -> Void) -> RunLock? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return RunLock(descriptor: -1) }
        var announced = false
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else {
                close(descriptor)
                return RunLock(descriptor: -1)
            }
            if !announced {
                announced = true
                onWait()
            }
            if isCancelled() {
                close(descriptor)
                return nil
            }
            Thread.sleep(forTimeInterval: poll)
        }
        return RunLock(descriptor: descriptor)
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
