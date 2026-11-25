import Foundation
import Testing

@Suite("Tarama")
struct ScanTests {
    let home: TempHome
    let engine: EvictEngine

    init() throws {
        home = try TempHome()
        engine = EvictEngine(policy: home.policy)
    }

    @Test("Klasördeki her dosya bir kez değerlendirilir")
    func everyFileIsSeenOnce() throws {
        try home.file("Desktop/a.bin")
        try home.file("Desktop/alt/b.bin")
        try home.file("Desktop/alt/daha alt/ç ğ.bin")

        let scan = engine.scan([home.desktop])

        #expect(scan.itemsSeen == 3)
        #expect(scan.skips[.notICloud]?.count == 3)
        #expect(scan.candidates.isEmpty)
        #expect(scan.errors.isEmpty)
    }

    @Test("Finder üst verisi ve eski yer tutucular sayılmaz")
    func metadataFilesAreIgnored() throws {
        try home.file("Desktop/.DS_Store")
        try home.file("Desktop/Icon\r")
        try home.file("Desktop/.rapor.pdf.icloud")
        try home.file("Desktop/gerçek.pdf")

        let scan = engine.scan([home.desktop])

        #expect(scan.itemsSeen == 1)
        #expect(scan.skipped.map(\.path) == [home.desktop + "/gerçek.pdf"])
    }

    @Test("Çöp ve sistem klasörlerinin içine girilmez")
    func systemFoldersAreNotEntered() throws {
        try home.file("Desktop/.Trash/silinmiş.bin")
        try home.file("Desktop/.Spotlight-V100/dizin.bin")
        try home.file("Desktop/kalan.bin")

        let scan = engine.scan([home.desktop])

        #expect(scan.skipped.map(\.path) == [home.desktop + "/kalan.bin"])
    }

    @Test("Hariç paket bütün olarak atlanır, içine girilmez")
    func excludedPackageIsSkippedWhole() throws {
        try home.file("Desktop/Foto.photoslibrary/database/Photos.sqlite", bytes: 4096)
        try home.file("Desktop/Foto.photoslibrary/originals/1.heic", bytes: 4096)

        let scan = engine.scan([home.desktop])

        #expect(scan.itemsSeen == 0)
        #expect(scan.skips[.excludedPackage]?.count == 1)
        #expect(scan.skipped.map(\.path) == [home.desktop + "/Foto.photoslibrary"])
        #expect(scan.skipped.first?.bytes == 8192)
    }

    @Test("İzinli konumların dışındaki yol taranmaz")
    func pathOutsideRootsIsNotScanned() throws {
        let outside = try home.file("Downloads/x.bin")

        let scan = engine.scan([outside])

        #expect(scan.itemsSeen == 0)
        #expect(scan.skips[.outsideRoots]?.count == 1)
        #expect(scan.inputs.isEmpty)
    }

    @Test("Notability klasörü gezilmeden atlanır")
    func selfDownloadingContainerIsNotWalked() throws {
        let folder = try home.folder("Library/Mobile Documents/ZP9ZJ4EF3S~com~gingerlabs~Notability/Documents")
        try home.file("Library/Mobile Documents/ZP9ZJ4EF3S~com~gingerlabs~Notability/Documents/Not.nbn/Session.plist", bytes: 4096)

        let scan = engine.scan([folder])

        #expect(scan.itemsSeen == 0)
        #expect(scan.skips[.selfDownloadingApp]?.count == 1)
        #expect(scan.skipped.first?.bytes == 4096)
    }

    @Test("Aynı öğe iki kez seçilse de bir kez sayılır")
    func overlappingSelectionsCountOnce() throws {
        let file = try home.file("Desktop/alt/a.bin")
        try home.file("Desktop/alt/b.bin")

        let scan = engine.scan([home.desktop + "/alt", file, file])

        #expect(scan.itemsSeen == 2)
        #expect(scan.skips[.notICloud]?.count == 2)
    }

    @Test("Var olmayan yol hata olarak bildirilir")
    func missingPathIsAnError() {
        let scan = engine.scan([home.desktop + "/yok.bin"])

        #expect(scan.errors.map(\.path) == [home.desktop + "/yok.bin"])
        #expect(scan.itemsSeen == 0)
    }

    @Test("Masaüstü kısayolu (symlink) izlenmez")
    func symlinksAreNotFollowed() throws {
        let target = try home.folder("Documents/hedef")
        try home.file("Documents/hedef/a.bin")
        try FileManager.default.createSymbolicLink(atPath: home.desktop + "/kısayol", withDestinationPath: target)

        let scan = engine.scan([home.desktop])

        #expect(scan.itemsSeen == 0)
    }
}
