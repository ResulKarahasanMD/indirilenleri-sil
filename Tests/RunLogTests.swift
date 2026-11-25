import Foundation
import Testing

@Suite("Çalıştırma kaydı")
struct RunLogTests {
    @Test("Kaçış karakterleri geri çözülür", arguments: ["plain", "tab\tin", "new\nline", "back\\slash\\t", "cr\r", "Ğ/İ\u{0307}"])
    func escapeRoundTrip(text: String) {
        let escaped = RunLog.escape(text)
        #expect(RunLog.unescape(escaped) == text)
        #expect(!escaped.contains("\t"))
        #expect(!escaped.contains("\n"))
    }

    @Test("Yazılan kayıtlar aynen okunur")
    func writeThenRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runlog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try RunLog(directory: dir, id: "t")
        log.write(.evicted, bytes: 4096, path: "/x/a\tb.txt")
        log.write(.skip, reason: SkipReason.uploading.rawValue, bytes: 10, path: "/x/new\nline")
        let rows = try RunLog.read(log.url)
        #expect(rows.map(\.action) == ["evicted", "skip"])
        #expect(rows.map(\.path) == ["/x/a\tb.txt", "/x/new\nline"])
        #expect(rows.map(\.bytes) == [4096, 10])
        #expect(rows.map(\.reason) == ["", "yukleniyor"])
    }

    @Test("Sekme ve satır sonu içeren hata metni kaydı bozmaz")
    func reasonWithTabsAndNewlinesSurvives() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runlog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try RunLog(directory: dir, id: "t")
        log.write(.error, reason: "satır1\nsatır2\tsekmeli \\ ters bölü", bytes: 42, path: "/x/a.txt")
        log.write(.evicted, bytes: 7, path: "/x/b.txt")
        let rows = try RunLog.read(log.url)
        #expect(rows.map(\.action) == ["error", "evicted"])
        #expect(rows.first?.reason == "satır1\nsatır2\tsekmeli \\ ters bölü")
        #expect(rows.map(\.bytes) == [42, 7])
        #expect(rows.map(\.path) == ["/x/a.txt", "/x/b.txt"])
    }

    @Test("Yazılamayan kayıt uygulamayı düşürmez, hatayı bildirir")
    func failedWriteIsReportedNotFatal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("salt-okur.tsv")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        // A handle that cannot be written to stands in for a full disk.
        let log = RunLog(url: url, handle: try FileHandle(forReadingFrom: url))

        log.write(.evicted, bytes: 1, path: "/x/a")
        log.write(.evicted, bytes: 1, path: "/x/b")

        let failure = try #require(log.failure)
        #expect(!failure.isEmpty)
    }

    @Test("En yeni kayıt dosya adına göre değil yazılma zamanına göre seçilir")
    func latestIsChosenByModificationDate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files: [(name: String, year: Int)] = [("z_eski.tsv", 2020), ("a_yeni.tsv", 2025), ("m_orta.tsv", 2023), ("not.txt", 2026)]
        for file in files {
            let url = dir.appendingPathComponent(file.name)
            FileManager.default.createFile(atPath: url.path, contents: Data())
            let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: file.year, month: 6, day: 1)))
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }

        #expect(RunLog.latest(in: dir)?.lastPathComponent == "a_yeni.tsv")
    }

    @Test("Kayıt klasörü yoksa en yeni kayıt da yoktur")
    func latestOfMissingDirectoryIsNil() {
        #expect(RunLog.latest(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")) == nil)
    }

    @Test("Kayıt, taramanın dokunmadıklarını nedenleriyle içerir")
    func recordsWhatTheScanLeftAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runlog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var scan = ScanResult()
        scan.skip(.uploading, path: "/x/yükleniyor.bin", bytes: 10)
        scan.skip(.alreadyEvicted, path: "/x/bulutta.bin", bytes: 0)
        scan.addError("/x/okunamaz.bin", "izin yok")
        scan.addCloudOnlyFolder("/x/bulut klasörü")

        let log = try RunLog(directory: dir, id: "t")
        log.record(scan)

        let rows = try RunLog.read(log.url)
        #expect(rows.map(\.action) == ["skip", "error", "cloud_only_folder"])
        #expect(rows.map(\.reason) == ["yukleniyor", "izin yok", ""])
        #expect(rows.map(\.bytes) == [10, 0, 0])
        #expect(rows.map(\.path) == ["/x/yükleniyor.bin", "/x/okunamaz.bin", "/x/bulut klasörü"])
    }
}
