import Foundation
import Synchronization
import Testing

@Suite("Tarama: iCloud durumuna göre")
struct ScanCloudTests {
    let home: TempHome

    init() throws { home = try TempHome() }

    func engine(_ cloud: FakeCloud, hooks: EvictEngine.Hooks = .init()) -> EvictEngine {
        EvictEngine(policy: home.policy, files: cloud.files, hooks: hooks)
    }

    @Test("Yüklenmiş dosyalar diskte kapladıkları yerle aday olur")
    func uploadedFilesAreCandidates() throws {
        let small = try home.file("Desktop/küçük.bin", bytes: 4096)
        let big = try home.file("Desktop/alt/büyük.bin", bytes: 16384)

        let scan = engine(FakeCloud()).scan([home.desktop])

        #expect(scan.candidates.sorted { $0.bytes < $1.bytes } == [
            Candidate(path: small, bytes: 4096, isPackage: false),
            Candidate(path: big, bytes: 16384, isPackage: false),
        ])
        #expect(scan.candidateBytes == 20480)
        #expect(scan.skips.isEmpty)
    }

    @Test("Yüklenmekte olan dosya aday olmaz")
    func uploadingFileIsSkipped() throws {
        let ready = try home.file("Desktop/hazır.bin", bytes: 4096)
        let busy = try home.file("Desktop/yükleniyor.bin", bytes: 8192)
        var script = FakeCloud.Script()
        script.states[busy] = ItemState(isUbiquitous: true, download: .current, isUploaded: false, isUploading: true,
                                        modified: FakeCloud.uploaded.modified)

        let scan = engine(FakeCloud(script)).scan([home.desktop])

        #expect(scan.candidates.map(\.path) == [ready])
        #expect(scan.skipped == [SkippedItem(reason: .uploading, path: busy, bytes: 8192)])
    }

    @Test("Paket tek aday olur, boyutu içindekilerin toplamıdır")
    func packageIsOneCandidate() throws {
        try home.file("Desktop/Rapor.rtfd/TXT.rtf", bytes: 4096)
        try home.file("Desktop/Rapor.rtfd/ek/resim.png", bytes: 8192)

        let cloud = FakeCloud()
        let scan = engine(cloud).scan([home.desktop])

        #expect(scan.candidates == [Candidate(path: home.desktop + "/Rapor.rtfd", bytes: 12288, isPackage: true)])
        #expect(cloud.stateReads == [home.desktop + "/Rapor.rtfd"])
    }

    @Test("Hariç paketin içinden yapılan seçim paketin kendisi sayılır", arguments: [
        "Desktop/Foto.photoslibrary/database/Photos.sqlite",
        "Desktop/Foto.photoslibrary/database",
    ])
    func selectionInsideExcludedPackage(selected: String) throws {
        try home.file("Desktop/Foto.photoslibrary/database/Photos.sqlite", bytes: 4096)
        let package = home.desktop + "/Foto.photoslibrary"

        let cloud = FakeCloud()
        let scan = engine(cloud).scan([home.path + "/" + selected])

        #expect(scan.candidates.isEmpty)
        #expect(scan.skipped == [SkippedItem(reason: .excludedPackage, path: package, bytes: 4096)])
        #expect(scan.inputs == [package])
        #expect(cloud.stateReads.isEmpty)
    }

    @Test("Paketin içinden yapılan seçim paketi bütün olarak aday yapar")
    func selectionInsidePackage() throws {
        let inner = try home.file("Desktop/Rapor.rtfd/TXT.rtf", bytes: 4096)
        try home.file("Desktop/Rapor.rtfd/ek.bin", bytes: 8192)
        let package = home.desktop + "/Rapor.rtfd"

        let scan = engine(FakeCloud()).scan([inner])

        #expect(scan.candidates == [Candidate(path: package, bytes: 12288, isPackage: true)])
        #expect(scan.inputs == [package])
    }

    @Test("Durumu okunamayan dosya 'iCloud dışı' değil hata olarak bildirilir")
    func unreadableStateIsAnError() throws {
        let locked = try home.file("Desktop/okunamaz.bin", bytes: 4096)
        let fine = try home.file("Desktop/okunur.bin", bytes: 4096)
        var script = FakeCloud.Script()
        script.unreadable = [locked]

        let scan = engine(FakeCloud(script)).scan([home.desktop])

        #expect(scan.errors.map(\.path) == [locked])
        #expect(scan.skips.isEmpty)
        #expect(scan.candidates.map(\.path) == [fine])
    }

    @Test("Yalnız bulutta duran klasörün içine bakılmaz")
    func cloudOnlyFolderIsNeverListed() throws {
        let folder = try home.folder("Desktop/bulutta")
        let child = try home.file("Desktop/bulutta/içerik.bin", bytes: 4096)
        let local = try home.file("Desktop/yerel.bin", bytes: 4096)
        var script = FakeCloud.Script()
        script.dataless = [folder]

        let cloud = FakeCloud(script)
        let scan = engine(cloud).scan([home.desktop])

        #expect(scan.cloudOnlyFolders == 1)
        #expect(scan.candidates.map(\.path) == [local])
        #expect(!cloud.stateReads.contains(child))
        #expect(scan.itemsSeen == 1)
    }

    @Test("Yalnız bulutta duran dosya durumu sorulmadan sayılır")
    func cloudOnlyFileIsCountedWithoutAsking() throws {
        let gone = try home.file("Desktop/bulutta.bin", bytes: 4096)
        var script = FakeCloud.Script()
        script.dataless = [gone]

        let cloud = FakeCloud(script)
        let scan = engine(cloud).scan([home.desktop])

        #expect(scan.skips == [.alreadyEvicted: Tally(count: 1, bytes: 0)])
        #expect(scan.skipped.isEmpty)
        #expect(cloud.stateReads.isEmpty)
    }

    @Test("Diskte yer kaplamayan dosya aday olmaz")
    func emptyFileIsNotACandidate() throws {
        let empty = try home.file("Desktop/boş.txt", bytes: 0)

        let scan = engine(FakeCloud()).scan([home.desktop])

        #expect(scan.candidates.isEmpty)
        #expect(scan.skipped == [SkippedItem(reason: .nothingToFree, path: empty, bytes: 0)])
    }

    @Test("Aynı öğe iki kez seçilirse girdi listesinde bir kez görünür")
    func repeatedInputIsListedOnce() throws {
        let file = try home.file("Desktop/a.bin", bytes: 4096)

        let scan = engine(FakeCloud()).scan([file, file])

        #expect(scan.inputs == [file])
        #expect(scan.candidates.count == 1)
    }

    @Test("Durdurulan tarama kalan dosyalara bakmaz")
    func cancelledScanStopsLooking() throws {
        for index in 0..<40 { try home.file("Desktop/\(index).bin", bytes: 4096) }
        let cloud = FakeCloud()
        let looked = Mutex(0)
        let hooks = EvictEngine.Hooks(isCancelled: { looked.withLock { $0 += 1; return $0 > 10 } })

        let scan = engine(cloud, hooks: hooks).scan([home.desktop])

        #expect(scan.itemsSeen < 40)
        #expect(scan.itemsSeen > 0)
    }

    @Test("Uzun taramada ilerleme bildirilir")
    func scanReportsProgress() throws {
        for index in 0..<260 { try home.file("Desktop/\(index).bin", bytes: 4096) }
        let reports = Mutex<[Progress]>([])
        let hooks = EvictEngine.Hooks(progress: { report in reports.withLock { $0.append(report) } })

        _ = engine(FakeCloud(), hooks: hooks).scan([home.desktop])

        #expect(reports.withLock { $0 } == [.scanning(items: 250, evictableBytes: 250 * 4096)])
    }
}
