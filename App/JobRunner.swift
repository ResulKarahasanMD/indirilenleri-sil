import Foundation
import Synchronization

/// One request to evict: what was selected, and how.
struct Job: Equatable, Sendable {
    let paths: [String]
    /// Nothing was selected: the paths are the folder a Finder window shows.
    let wholeFolder: Bool
}

enum JobPhase: Equatable, Sendable {
    case scanning
    case evicting(total: Int)
}

/// Set from the main thread, read by the engine's threads.
final class CancelFlag: Sendable {
    private let value = Mutex(false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}

/// What a job shows and asks. The app answers with panels and alerts, the tests with a script.
@MainActor
protocol JobUI: AnyObject, Sendable {
    /// A phase that can take a while begins. `stop` is set when the user wants out.
    func begin(_ phase: JobPhase, stop: CancelFlag)
    func show(_ progress: Progress)
    func end()
    func nothingToEvict(_ scan: ScanResult, for job: Job)
    func confirm(_ scan: ScanResult, for job: Job) -> Bool
    func finished(_ result: EvictResult, log: URL?) async
}

/// A job from selection to notification: scan, ask, evict, report. Nothing is evicted unless the
/// user said yes to the numbers the scan produced.
@MainActor
struct JobRunner {
    let ui: any JobUI
    var logDirectory = RunLog.defaultDirectory()
    var engine: @Sendable (EvictEngine.Hooks) -> EvictEngine = { EvictEngine(hooks: $0) }

    func run(_ job: Job) async {
        let stop = CancelFlag()
        let ui = ui
        let engine = engine(EvictEngine.Hooks(
            isCancelled: { stop.isSet },
            // Main-actor jobs run in the order they were sent, so reports arrive in order and
            // before this job goes on after the work that produced them.
            progress: { progress in Task { @MainActor in ui.show(progress) } }))

        ui.begin(.scanning, stop: stop)
        let scan = await Background.run { engine.scan(job.paths) }
        ui.end()
        guard !stop.isSet else { return }
        guard !scan.candidates.isEmpty else { return ui.nothingToEvict(scan, for: job) }
        guard ui.confirm(scan, for: job) else { return }

        ui.begin(.evicting(total: scan.candidates.count), stop: stop)
        let logDirectory = logDirectory
        let run = await Background.run { engine.run(scan, logDirectory: logDirectory) }
        ui.end()
        await ui.finished(run.result, log: run.log)
    }
}

enum Background {
    /// Runs blocking work on a utility thread of its own: off the main actor, and off the
    /// cooperative pool, whose few threads must not be held for minutes.
    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: work()) }
        }
    }
}
