import Foundation
import Testing

@Suite("Report text")
struct ReportTests {
    @Test("Skip reasons start with the ones the user can do something about")
    func actionableReasonsComeFirst() {
        let lines = Report.skipLines([
            .alreadyEvicted: Tally(count: 9, bytes: 0),
            .notICloud: Tally(count: 2, bytes: 0),
            .uploading: Tally(count: 1, bytes: 0),
        ])
        #expect(lines == ["yükleniyor: 1", "iCloud dışı: 2", "zaten bırakılmış: 9"])
    }

    @Test("Every reason seen appears in the report")
    func everyReasonIsListed() {
        var skips: [SkipReason: Tally] = [:]
        for reason in SkipReason.allCases { skips[reason] = Tally(count: 1, bytes: 0) }

        #expect(SkipReason.allCases.count == 16)
        #expect(Report.skipLines(skips).count == 16)
    }

    @Test("Files iCloud refused do not go under the 'state changed' heading")
    func refusalsHaveTheirOwnHeading() {
        var result = EvictResult()
        result.refused[.nonEvictable] = Tally(count: 3, bytes: 0)

        let text = Report.evict(result)

        #expect(text.contains("iCloud'un reddettiği:\n  iCloud bırakmaya izin vermiyor: 3"))
        #expect(!text.contains("durumu değişip"))
    }

    @Test("Files that changed after the scan stay under their own heading")
    func changesKeepTheirHeading() {
        var result = EvictResult()
        result.changed[.uploading] = Tally(count: 2, bytes: 0)

        let text = Report.evict(result)

        #expect(text.contains("taramadan sonra durumu değişip atlanan:\n  yükleniyor: 2"))
        #expect(!text.contains("reddettiği"))
    }

    @Test("Missing files, unconfirmed files and a log problem appear in the report")
    func leftoversAreReported() {
        var result = EvictResult()
        result.missing = Tally(count: 4, bytes: 0)
        result.unconfirmed = Tally(count: 5, bytes: 0)
        result.logFailure = "diskte yer kalmadı"

        let lines = Report.evict(result).components(separatedBy: "\n")

        #expect(lines.contains { $0.hasPrefix("çalışma sırasında taşınan ya da silinen: 4") })
        #expect(lines.contains { $0.hasPrefix("istek yapıldı, sonucu beklenmedi: 5") })
        #expect(lines.contains("kayıt tutulamadı: diskte yer kalmadı"))
    }

    @Test("The notification does not describe a refusal as 'son anda değişti' (changed at the last moment)")
    func notificationNamesRefusals() {
        var result = EvictResult()
        result.evicted = Tally(count: 10, bytes: 0)
        result.refused[.nonEvictable] = Tally(count: 3, bytes: 0)

        let body = Report.notification(result).body

        #expect(body == "3 dosyayı iCloud bırakmadı")
    }

    @Test("The notification counts everything left behind")
    func notificationCountsEverythingLeft() {
        var result = EvictResult()
        result.stillLocal = Tally(count: 1, bytes: 0)
        result.changed[.uploading] = Tally(count: 2, bytes: 0)
        result.missing = Tally(count: 4, bytes: 0)
        result.errors = [PathIssue(path: "/x", message: "m")]
        result.logFailure = "yazılamadı"

        let body = Report.notification(result).body

        #expect(body == "1 dosya diskte kaldı · 2 dosya son anda değişti · 4 dosya yerinde yok · 1 hata · kayıt tutulamadı")
    }

    @Test("If everything was evicted, the notification states only the result")
    func notificationForACleanRun() {
        var result = EvictResult()
        result.evicted = Tally(count: 1234, bytes: 0)

        #expect(Report.notification(result).body == "1.234 dosya artık yalnız iCloud'da")
    }
}

@Suite("Command-line exit status")
struct ExitStatusTests {
    @Test("0 if every candidate was evicted")
    func complete() {
        var result = EvictResult()
        result.evicted = Tally(count: 3, bytes: 0)
        #expect(CLI.exitStatus(for: result, candidates: 3) == 0)
        #expect(CLI.exitStatus(for: EvictResult(), candidates: 0) == 0)
    }

    @Test("1 if no candidate could be evicted")
    func nothingEvicted() {
        var result = EvictResult()
        result.refused[.nonEvictable] = Tally(count: 3, bytes: 0)
        #expect(CLI.exitStatus(for: result, candidates: 3) == 1)
    }

    @Test("1 if the log could not be kept")
    func logFailure() {
        var result = EvictResult()
        result.evicted = Tally(count: 3, bytes: 0)
        result.logFailure = "yazılamadı"
        #expect(CLI.exitStatus(for: result, candidates: 3) == 1)
    }
}

@Suite("Finder selection")
struct FinderSelectionTests {
    @Test("Selected items are taken as they are")
    func selectedItems() {
        let selection = FinderSelection.selection(from: ["0", "/Users/u/Desktop/a.pdf", "/Users/u/Desktop/satır\nsonu.txt"])
        #expect(selection == .init(paths: ["/Users/u/Desktop/a.pdf", "/Users/u/Desktop/satır\nsonu.txt"], wholeFolder: false))
    }

    @Test("The trailing slash of a folder path is dropped")
    func trailingSlashIsDropped() {
        let selection = FinderSelection.selection(from: ["1", "/Users/u/Desktop/klasör/"])
        #expect(selection == .init(paths: ["/Users/u/Desktop/klasör"], wholeFolder: true))
        #expect(FinderSelection.selection(from: ["0", "/"])?.paths == ["/"])
    }

    @Test("With neither a selection nor a window, the path list is empty")
    func nothingSelected() {
        #expect(FinderSelection.selection(from: ["0"]) == .init(paths: [], wholeFolder: false))
    }

    @Test("An unexpected reply from Finder does not count as a selection", arguments: [[String](), ["evet", "/a"], ["2"]])
    func malformedAnswer(items: [String]) {
        #expect(FinderSelection.selection(from: items) == nil)
    }
}
