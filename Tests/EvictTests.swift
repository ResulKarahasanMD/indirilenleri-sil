import Foundation
import Testing

@Suite("Eviction")
struct EvictTests {
    let home: TempHome

    init() throws { home = try TempHome() }

    func engine(_ cloud: FakeCloud, hooks: EvictEngine.Hooks = .init(), stall: TimeInterval = 0.3) -> EvictEngine {
        var engine = EvictEngine(policy: home.policy, files: cloud.files, hooks: hooks)
        engine.stallTimeout = stall
        engine.pollInterval = 0.01
        engine.lockURL = URL(fileURLWithPath: home.path + "/kilit")
        return engine
    }

    /// Real files on the Desktop, each 4096 bytes on disk, as the scan would hand them over.
    func candidates(_ names: String...) throws -> [Candidate] {
        try names.map { Candidate(path: try home.file("Desktop/" + $0, bytes: 4096), bytes: 4096, isPackage: false) }
    }

    func log() throws -> RunLog {
        try RunLog(directory: URL(fileURLWithPath: home.path + "/kayıt"), id: "t")
    }

    // MARK: Counting

    @Test("Files that leave the disk count as evicted and are logged")
    func confirmedEvictionsAreCounted() throws {
        let items = try candidates("a.bin", "b.bin", "c.bin")
        let cloud = FakeCloud()
        let log = try log()

        let result = engine(cloud).evict(items, log: log)

        #expect(result.evicted == Tally(count: 3, bytes: 12288))
        #expect(cloud.evicted.sorted() == items.map(\.path).sorted())
        let rows = try RunLog.read(log.url)
        #expect(rows.map(\.action) == ["evicted", "evicted", "evicted"])
        #expect(rows.map(\.bytes) == [4096, 4096, 4096])
        #expect(result.stillLocal.count == 0)
        #expect(result.errors.isEmpty)
    }

    @Test("A late-completing eviction is waited for")
    func slowEvictionIsWaitedFor() throws {
        let items = try candidates("a.bin")
        var script = FakeCloud.Script()
        script.pollsToSettle = 5

        let result = engine(FakeCloud(script)).evict(items)

        #expect(result.evicted == Tally(count: 1, bytes: 4096))
    }

    @Test("A file whose data stays on disk does not count as evicted")
    func dataStillOnDiskIsNotCounted() throws {
        let items = try candidates("kalan.bin", "giden.bin")
        var script = FakeCloud.Script()
        script.afterEvict[items[0].path] = .staysLocal
        let log = try log()

        let result = engine(FakeCloud(script)).evict(items, log: log)

        #expect(result.evicted == Tally(count: 1, bytes: 4096))
        #expect(result.stillLocal == Tally(count: 1, bytes: 4096))
        let rows = try RunLog.read(log.url)
        #expect(rows.first { $0.path == items[0].path }?.action == "evict_noop")
    }

    @Test("A file that disappears during the run does not count as evicted")
    func vanishedFileIsNotCounted() throws {
        let items = try candidates("taşınan.bin", "giden.bin")
        var script = FakeCloud.Script()
        script.afterEvict[items[0].path] = .vanishes
        let log = try log()

        let result = engine(FakeCloud(script)).evict(items, log: log)

        #expect(result.evicted == Tally(count: 1, bytes: 4096))
        #expect(result.missing == Tally(count: 1, bytes: 4096))
        let rows = try RunLog.read(log.url)
        #expect(rows.first { $0.path == items[0].path }?.action == "missing")
    }

    @Test("No request is sent for a file deleted after the scan")
    func fileGoneBeforeTheRequestIsNotRequested() throws {
        let items = try candidates("silinen.bin")
        try FileManager.default.removeItem(atPath: items[0].path)
        let cloud = FakeCloud()

        let result = engine(cloud).evict(items)

        #expect(cloud.evicted.isEmpty)
        #expect(result.missing.count == 1)
        #expect(result.evicted.count == 0)
    }

    @Test("No request is sent for a file emptied after the scan")
    func fileEmptiedAfterTheScanIsNotRequested() throws {
        let items = try candidates("boşalan.bin")
        try Data().write(to: URL(fileURLWithPath: items[0].path))
        let cloud = FakeCloud()

        let result = engine(cloud).evict(items)

        #expect(cloud.evicted.isEmpty)
        #expect(result.changed == [.nothingToFree: Tally(count: 1, bytes: 4096)])
        #expect(result.evicted.count == 0)
    }

    // MARK: Refusals and changes

    @Test("A file whose state changed after the scan is skipped")
    func changedItemIsSkipped() throws {
        let items = try candidates("düzenlenen.bin")
        var script = FakeCloud.Script()
        script.states[items[0].path] = ItemState(isUbiquitous: true, download: .current, isUploaded: false,
                                                 isUploading: true, modified: FakeCloud.uploaded.modified)
        let cloud = FakeCloud(script)

        let result = engine(cloud).evict(items)

        #expect(cloud.evicted.isEmpty)
        #expect(result.changed == [.uploading: Tally(count: 1, bytes: 4096)])
        #expect(result.refused.isEmpty)
    }

    @Test("An iCloud refusal counts as 'refused', not 'state changed'")
    func refusalIsNotAChange() throws {
        let items = try candidates("reddedilen.bin")
        var script = FakeCloud.Script()
        script.refusals[items[0].path] = NSError(domain: NSCocoaErrorDomain, code: 512, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "NSFileProviderErrorDomain", code: -2008),
        ])
        let log = try log()

        let result = engine(FakeCloud(script)).evict(items, log: log)

        #expect(result.refused == [.nonEvictable: Tally(count: 1, bytes: 4096)])
        #expect(result.changed.isEmpty)
        #expect(result.errors.isEmpty)
        let rows = try RunLog.read(log.url)
        #expect(rows.map(\.action) == ["refused"])
        #expect(rows.map(\.reason) == ["birakilamaz"])
    }

    @Test("An unrecognized error is reported as an error, together with its cause")
    func unknownFailureIsAnError() throws {
        let items = try candidates("hatalı.bin")
        var script = FakeCloud.Script()
        script.refusals[items[0].path] = NSError(domain: NSCocoaErrorDomain, code: 257)

        let result = engine(FakeCloud(script)).evict(items)

        #expect(result.errors.map(\.path) == [items[0].path])
        #expect(result.errors.first?.message.hasPrefix("NSCocoaErrorDomain 257") == true)
        #expect(result.refused.isEmpty)
    }

    @Test("No request is sent for a file whose state cannot be read")
    func unreadableItemIsNotRequested() throws {
        let items = try candidates("okunamaz.bin")
        var script = FakeCloud.Script()
        script.unreadable = [items[0].path]
        let cloud = FakeCloud(script)

        let result = engine(cloud).evict(items)

        #expect(cloud.evicted.isEmpty)
        #expect(result.errors.map(\.path) == [items[0].path])
        #expect(result.changed.isEmpty)
    }

    // MARK: Stopping

    @Test("'Durdur' (Stop) ends the wait while evictions are being confirmed")
    func cancelEndsTheWaitForConfirmation() throws {
        let items = try candidates("bekleyen.bin")
        var script = FakeCloud.Script()
        script.afterEvict[items[0].path] = .staysLocal
        let stop = Flag()
        let hooks = EvictEngine.Hooks(isCancelled: { stop.isSet },
                                      progress: { if case .confirming = $0 { stop.set() } })

        let started = Date()
        let result = engine(FakeCloud(script), hooks: hooks, stall: 3).evict(items)

        #expect(Date().timeIntervalSince(started) < 1.5)
        #expect(result.cancelled)
        #expect(result.unconfirmed == Tally(count: 1, bytes: 4096))
        #expect(result.stillLocal.count == 0)
    }

    @Test("'Durdur' (Stop) while waiting for another run exits without touching anything")
    func cancelWhileWaitingForTheLock() throws {
        let items = try candidates("a.bin")
        let cloud = FakeCloud()
        let stop = Flag()
        let engine = engine(cloud, hooks: EvictEngine.Hooks(
            isCancelled: { stop.isSet },
            progress: { if $0 == .waitingForOtherRun { stop.set() } }))
        let other = HeldLock(engine.lockURL)

        let run = BackgroundRun { engine.evict(items) }
        let result = run.result(within: 2)
        other.release()

        #expect(result?.cancelled == true)
        #expect(result?.evicted.count == 0)
        #expect(cloud.evicted.isEmpty)
        _ = run.result(within: 10)
    }

    @Test("A second run waits for the first to finish, then continues")
    func secondRunWaitsForTheFirst() throws {
        let items = try candidates("a.bin")
        let cloud = FakeCloud()
        let reports = Collected<Progress>()
        let engine = engine(cloud, hooks: EvictEngine.Hooks(progress: { reports.add($0) }))
        let other = HeldLock(engine.lockURL)

        let run = BackgroundRun { engine.evict(items) }
        #expect(run.result(within: 0.3) == nil)
        #expect(cloud.evicted.isEmpty)
        other.release()
        let result = try #require(run.result(within: 10))

        #expect(result.evicted.count == 1)
        #expect(reports.all.first == .waitingForOtherRun)
    }

    // MARK: Progress

    @Test("Progress never goes backward and completes when the job is done")
    func progressNeverGoesBack() throws {
        let items = try (0..<120).map { Candidate(path: try home.file("Desktop/\($0).bin", bytes: 4096), bytes: 4096, isPackage: false) }
        var script = FakeCloud.Script()
        script.pollsToSettle = 2
        script.refusals[items[7].path] = NSError(domain: "NSFileProviderErrorDomain", code: -2008)
        let reports = Collected<Progress>()
        let hooks = EvictEngine.Hooks(progress: { reports.add($0) })

        _ = engine(FakeCloud(script), hooks: hooks).evict(items)

        let fractions = reports.all.compactMap(\.fraction)
        #expect(fractions.count >= 3)
        #expect(fractions == fractions.sorted())
        #expect(fractions.last == 1)
        #expect(fractions.allSatisfy { (0...1).contains($0) })
    }

    @Test("No fraction is reported when there is no work to measure", arguments: [
        Progress.scanning(items: 10, evictableBytes: 1), .waitingForOtherRun, .requesting(done: 0, total: 0),
    ])
    func noFractionWithoutWork(report: Progress) {
        #expect(report.fraction == nil)
    }

    // MARK: Whole run

    @Test("A run writes what the scan skipped and what was evicted to the same log")
    func runKeepsOneRecord() throws {
        let kept = try home.file("Desktop/yükleniyor.bin", bytes: 8192)
        let gone = try home.file("Desktop/giden.bin", bytes: 4096)
        var script = FakeCloud.Script()
        script.states[kept] = ItemState(isUbiquitous: true, download: .current, isUploaded: false, isUploading: true,
                                        modified: FakeCloud.uploaded.modified)
        let engine = engine(FakeCloud(script))
        let logs = URL(fileURLWithPath: home.path + "/kayıt")

        let run = engine.run(engine.scan([home.desktop]), logDirectory: logs)

        #expect(run.result.evicted == Tally(count: 1, bytes: 4096))
        #expect(run.result.logFailure == nil)
        let rows = try RunLog.read(try #require(run.log))
        #expect(rows.map(\.action) == ["skip", "evicted"])
        #expect(rows.map(\.path) == [kept, gone])
    }

    @Test("Even if the log cannot be opened, eviction goes ahead and the reason is reported")
    func runGoesOnWithoutALog() throws {
        let file = try home.file("Desktop/a.bin", bytes: 4096)
        let blocker = try home.file("engel")
        let cloud = FakeCloud()
        let engine = engine(cloud)

        // A folder cannot be created below a plain file: the log directory is unusable.
        let run = engine.run(engine.scan([home.desktop]), logDirectory: URL(fileURLWithPath: blocker + "/kayıt"))

        #expect(cloud.evicted == [file])
        #expect(run.result.evicted.count == 1)
        #expect(run.log == nil)
        #expect(run.result.logFailure?.isEmpty == false)
    }

    // MARK: Completeness

    @Test("A run is complete if every candidate was evicted")
    func completeWhenEveryCandidateWasEvicted() {
        var result = EvictResult()
        result.evicted = Tally(count: 3, bytes: 300)
        #expect(result.isComplete(of: 3))
        #expect(EvictResult().isComplete(of: 0))
    }

    @Test("A single candidate that could not be evicted makes the run incomplete")
    func incompleteWhenAnythingWasLeft() {
        var refused = EvictResult()
        refused.evicted = Tally(count: 2, bytes: 200)
        refused.refused[.nonEvictable] = Tally(count: 1, bytes: 100)
        #expect(!refused.isComplete(of: 3))

        var cancelled = EvictResult()
        cancelled.evicted = Tally(count: 3, bytes: 300)
        cancelled.cancelled = true
        #expect(!cancelled.isComplete(of: 3))
    }

    // MARK: Verify

    @Test("Verification reports the current state of the evicted items")
    func verifyReportsWhereEvictedItemsAre() throws {
        let back = try home.file("Desktop/geri inen.bin", bytes: 8192)
        let still = try home.file("Desktop/bulutta.bin", bytes: 4096)
        let never = try home.file("Desktop/hiç bırakılmayan.bin", bytes: 4096)
        var script = FakeCloud.Script()
        script.dataless = [still]
        func row(_ action: String, _ path: String) -> RunLog.Row {
            RunLog.Row(time: "", action: action, reason: "", bytes: 1, path: path)
        }

        let result = engine(FakeCloud(script)).verify([
            row("evicted", back), row("evicted", still), row("evicted", home.desktop + "/silinmiş.bin"),
            row("skip", never), row("evict_noop", never),
        ])

        #expect(result.stillEvicted == 1)
        #expect(result.redownloaded == [SizedPath(path: back, bytes: 8192)])
        #expect(result.missing == 1)
    }
}
