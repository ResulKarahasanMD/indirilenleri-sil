import Foundation
import Testing

@Suite("Bırakma kararı")
struct EligibilityTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// An iCloud file that is fully uploaded and was last touched an hour ago.
    static func uploaded(_ edit: (inout ItemState) -> Void = { _ in }) -> ItemState {
        var s = ItemState(isUbiquitous: true, download: .current, isUploaded: true,
                          modified: now.addingTimeInterval(-3600))
        edit(&s)
        return s
    }

    struct UnsafeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let state: ItemState
        let reason: SkipReason
    }

    static let unsafeCases: [UnsafeCase] = [
        UnsafeCase(testDescription: "bulutta (dataless)", state: uploaded { $0.isDataless = true }, reason: .alreadyEvicted),
        UnsafeCase(testDescription: "indirilmemiş", state: uploaded { $0.download = .notDownloaded }, reason: .alreadyEvicted),
        UnsafeCase(testDescription: "iCloud dışı", state: uploaded { $0.isUbiquitous = false }, reason: .notICloud),
        UnsafeCase(testDescription: "eşitleme dışı", state: uploaded { $0.isExcludedFromSync = true }, reason: .excludedFromSync),
        UnsafeCase(testDescription: "çakışmalı", state: uploaded { $0.hasConflicts = true }, reason: .conflict),
        UnsafeCase(testDescription: "yükleniyor", state: uploaded { $0.isUploading = true }, reason: .uploading),
        UnsafeCase(testDescription: "yüklenmemiş", state: uploaded { $0.isUploaded = false }, reason: .notUploaded),
        UnsafeCase(testDescription: "iniyor", state: uploaded { $0.isDownloading = true }, reason: .downloading),
        UnsafeCase(testDescription: "bir dakika önce değişmiş", state: uploaded { $0.modified = now.addingTimeInterval(-60) }, reason: .recentlyModified),
        UnsafeCase(testDescription: "İndirileni Tut açık", state: uploaded { $0.isPinned = true }, reason: .keepDownloaded),
    ]

    @Test("Yüklenmiş dosya bırakılır", arguments: [ItemState.Download.current, .downloaded])
    func uploadedFileIsEvicted(download: ItemState.Download) {
        #expect(Eligibility.decide(Self.uploaded { $0.download = download }, localBytes: 4096, now: Self.now) == .evict)
    }

    @Test("Güvensiz durum kendi nedeniyle atlanır", arguments: unsafeCases)
    func unsafeStateIsSkipped(_ c: UnsafeCase) {
        #expect(Eligibility.decide(c.state, localBytes: 4096, now: Self.now) == .skip(c.reason))
    }

    @Test("Yüklenen dosya 'yüklenmedi' değil 'yükleniyor' diye raporlanır")
    func uploadingWinsOverNotUploaded() {
        let state = Self.uploaded { $0.isUploaded = false; $0.isUploading = true }
        #expect(Eligibility.decide(state, localBytes: 4096, now: Self.now) == .skip(.uploading))
    }

    @Test("Hakkında hiçbir şey bilinmeyen öğe bırakılmaz")
    func unknownItemIsNeverEvicted() {
        #expect(Eligibility.decide(ItemState(), localBytes: 4096, now: Self.now) != .evict)
    }

    struct AgeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        /// Seconds relative to "now"; nil when the date could not be read.
        let modified: TimeInterval?
        let changed: TimeInterval?
        let expected: Decision
    }

    static let month: TimeInterval = 30 * 86_400

    static let ageCases: [AgeCase] = [
        AgeCase(testDescription: "bir saat önce değişmiş", modified: -3600, changed: nil, expected: .evict),
        AgeCase(testDescription: "tam beş dakika önce değişmiş", modified: -300, changed: nil, expected: .evict),
        AgeCase(testDescription: "beş dakikadan bir saniye az", modified: -299, changed: nil, expected: .skip(.recentlyModified)),
        AgeCase(testDescription: "gelecek tarihli, bir saat önce dokunulmuş", modified: month, changed: -3600, expected: .evict),
        AgeCase(testDescription: "gelecek tarihli, bir dakika önce dokunulmuş", modified: month, changed: -60, expected: .skip(.recentlyModified)),
        AgeCase(testDescription: "gelecek tarihli, dokunulma zamanı bilinmiyor", modified: month, changed: nil, expected: .skip(.ageUnknown)),
        AgeCase(testDescription: "iki tarih de gelecekte", modified: month, changed: 60, expected: .skip(.ageUnknown)),
        AgeCase(testDescription: "hiçbir tarih okunamıyor", modified: nil, changed: nil, expected: .skip(.ageUnknown)),
        AgeCase(testDescription: "değişiklik tarihi yok, bir saat önce dokunulmuş", modified: nil, changed: -3600, expected: .evict),
    ]

    @Test("Dosyanın yaşı güvenilir tarihten hesaplanır", arguments: ageCases)
    func ageIsTakenFromATrustworthyDate(_ c: AgeCase) {
        let state = Self.uploaded {
            $0.modified = c.modified.map { Self.now.addingTimeInterval($0) }
            $0.changed = c.changed.map { Self.now.addingTimeInterval($0) }
        }
        #expect(Eligibility.decide(state, localBytes: 4096, now: Self.now) == c.expected)
    }

    @Test("Diskte yer kaplamayan dosya aday olmaz")
    func nothingToFree() {
        #expect(Eligibility.decide(Self.uploaded(), localBytes: 0, now: Self.now) == .skip(.nothingToFree))
    }

    @Test("iCloud dışı boş dosya 'iCloud dışı' diye raporlanır")
    func notICloudWinsOverNothingToFree() {
        let state = Self.uploaded { $0.isUbiquitous = false }
        #expect(Eligibility.decide(state, localBytes: 0, now: Self.now) == .skip(.notICloud))
    }
}
