import Foundation
import Testing

/// Answers the job's questions from a script and writes down what it was shown.
@MainActor
final class ScriptedUI: JobUI {
    var consent = true
    /// Presses "stop" as soon as this phase begins.
    var stopsDuring: JobPhase?
    private(set) var events: [String] = []
    private(set) var asked: ScanResult?
    private(set) var result: EvictResult?
    private(set) var log: URL?
    private(set) var reports: [Progress] = []

    func begin(_ phase: JobPhase, stop: CancelFlag) {
        events.append(phase == .scanning ? "tarama" : "bırakma")
        if phase == stopsDuring { stop.set() }
    }

    func show(_ progress: Progress) { reports.append(progress) }
    func end() { events.append("bitti") }
    func nothingToEvict(_ scan: ScanResult, for job: Job) { events.append("yapılacak iş yok") }

    func confirm(_ scan: ScanResult, for job: Job) -> Bool {
        events.append("onay")
        asked = scan
        return consent
    }

    func finished(_ result: EvictResult, log: URL?) async {
        events.append("sonuç")
        self.result = result
        self.log = log
    }
}

@Suite("Job flow")
@MainActor
struct JobRunnerTests {
    let home: TempHome
    let cloud: FakeCloud
    let ui = ScriptedUI()

    init() throws {
        home = try TempHome()
        cloud = FakeCloud()
    }

    func runner() -> JobRunner {
        let policy = home.policy
        let files = cloud.files
        let lock = URL(fileURLWithPath: home.path + "/kilit")
        return JobRunner(ui: ui, logDirectory: URL(fileURLWithPath: home.path + "/kayıt")) { hooks in
            var engine = EvictEngine(policy: policy, files: files, hooks: hooks)
            engine.pollInterval = 0.01
            engine.lockURL = lock
            return engine
        }
    }

    @Test("Without confirmation no file is evicted")
    func nothingIsEvictedWithoutConsent() async throws {
        try home.file("Desktop/a.bin", bytes: 4096)
        ui.consent = false

        await runner().run(Job(paths: [home.desktop], wholeFolder: false))

        #expect(cloud.evicted.isEmpty)
        #expect(ui.events == ["tarama", "bitti", "onay"])
        #expect(!FileManager.default.fileExists(atPath: home.path + "/kayıt"))
    }

    @Test("The files confirmed are the ones the scan showed, and the result is reported")
    func consentEvictsWhatWasShown() async throws {
        let a = try home.file("Desktop/a.bin", bytes: 4096)
        let b = try home.file("Desktop/b.bin", bytes: 8192)

        await runner().run(Job(paths: [home.desktop], wholeFolder: false))

        #expect(ui.events == ["tarama", "bitti", "onay", "bırakma", "bitti", "sonuç"])
        #expect(ui.asked?.candidates.map(\.path).sorted() == [a, b])
        #expect(cloud.evicted.sorted() == [a, b])
        #expect(ui.result?.evicted == Tally(count: 2, bytes: 12288))
        let log = try #require(ui.log)
        #expect(try RunLog.read(log).map(\.action) == ["evicted", "evicted"])
    }

    @Test("No confirmation is asked for when there is nothing to evict")
    func noQuestionWhenThereIsNothingToEvict() async throws {
        try home.file("Desktop/boş.txt", bytes: 0)

        await runner().run(Job(paths: [home.desktop], wholeFolder: false))

        #expect(ui.events == ["tarama", "bitti", "yapılacak iş yok"])
        #expect(cloud.evicted.isEmpty)
    }

    @Test("No confirmation is asked for if the scan is stopped")
    func stoppedScanAsksNothing() async throws {
        try home.file("Desktop/a.bin", bytes: 4096)
        ui.stopsDuring = .scanning

        await runner().run(Job(paths: [home.desktop], wholeFolder: false))

        #expect(ui.events == ["tarama", "bitti"])
        #expect(cloud.evicted.isEmpty)
    }

    @Test("Progress during eviction reaches the screen")
    func progressReachesTheScreen() async throws {
        for index in 0..<60 { try home.file("Desktop/\(index).bin", bytes: 4096) }

        await runner().run(Job(paths: [home.desktop], wholeFolder: false))

        #expect(ui.reports.contains(.requesting(done: 50, total: 60)))
        #expect(ui.reports.last == .confirming(done: 60, total: 60, freedBytes: 60 * 4096))
    }
}
