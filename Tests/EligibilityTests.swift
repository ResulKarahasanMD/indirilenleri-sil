import Foundation
import Testing

@Suite("Eviction decision")
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
        UnsafeCase(testDescription: "in the cloud (dataless)", state: uploaded { $0.isDataless = true }, reason: .alreadyEvicted),
        UnsafeCase(testDescription: "not downloaded", state: uploaded { $0.download = .notDownloaded }, reason: .alreadyEvicted),
        UnsafeCase(testDescription: "outside iCloud", state: uploaded { $0.isUbiquitous = false }, reason: .notICloud),
        UnsafeCase(testDescription: "excluded from sync", state: uploaded { $0.isExcludedFromSync = true }, reason: .excludedFromSync),
        UnsafeCase(testDescription: "has conflicts", state: uploaded { $0.hasConflicts = true }, reason: .conflict),
        UnsafeCase(testDescription: "uploading", state: uploaded { $0.isUploading = true }, reason: .uploading),
        UnsafeCase(testDescription: "not uploaded", state: uploaded { $0.isUploaded = false }, reason: .notUploaded),
        UnsafeCase(testDescription: "downloading", state: uploaded { $0.isDownloading = true }, reason: .downloading),
        UnsafeCase(testDescription: "modified a minute ago", state: uploaded { $0.modified = now.addingTimeInterval(-60) }, reason: .recentlyModified),
        UnsafeCase(testDescription: "Keep Downloaded on", state: uploaded { $0.isPinned = true }, reason: .keepDownloaded),
    ]

    @Test("An uploaded file is evicted", arguments: [ItemState.Download.current, .downloaded])
    func uploadedFileIsEvicted(download: ItemState.Download) {
        #expect(Eligibility.decide(Self.uploaded { $0.download = download }, localBytes: 4096, now: Self.now) == .evict)
    }

    @Test("An unsafe state is skipped with its own reason", arguments: unsafeCases)
    func unsafeStateIsSkipped(_ c: UnsafeCase) {
        #expect(Eligibility.decide(c.state, localBytes: 4096, now: Self.now) == .skip(c.reason))
    }

    @Test("A file being uploaded is reported as 'uploading', not 'not uploaded'")
    func uploadingWinsOverNotUploaded() {
        let state = Self.uploaded { $0.isUploaded = false; $0.isUploading = true }
        #expect(Eligibility.decide(state, localBytes: 4096, now: Self.now) == .skip(.uploading))
    }

    @Test("An item nothing is known about is not evicted")
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
        AgeCase(testDescription: "modified an hour ago", modified: -3600, changed: nil, expected: .evict),
        AgeCase(testDescription: "modified exactly five minutes ago", modified: -300, changed: nil, expected: .evict),
        AgeCase(testDescription: "one second short of five minutes", modified: -299, changed: nil, expected: .skip(.recentlyModified)),
        AgeCase(testDescription: "future-dated, touched an hour ago", modified: month, changed: -3600, expected: .evict),
        AgeCase(testDescription: "future-dated, touched a minute ago", modified: month, changed: -60, expected: .skip(.recentlyModified)),
        AgeCase(testDescription: "future-dated, touch time unknown", modified: month, changed: nil, expected: .skip(.ageUnknown)),
        AgeCase(testDescription: "both dates in the future", modified: month, changed: 60, expected: .skip(.ageUnknown)),
        AgeCase(testDescription: "no date can be read", modified: nil, changed: nil, expected: .skip(.ageUnknown)),
        AgeCase(testDescription: "no modification date, touched an hour ago", modified: nil, changed: -3600, expected: .evict),
    ]

    @Test("A file's age is computed from a trustworthy date", arguments: ageCases)
    func ageIsTakenFromATrustworthyDate(_ c: AgeCase) {
        let state = Self.uploaded {
            $0.modified = c.modified.map { Self.now.addingTimeInterval($0) }
            $0.changed = c.changed.map { Self.now.addingTimeInterval($0) }
        }
        #expect(Eligibility.decide(state, localBytes: 4096, now: Self.now) == c.expected)
    }

    @Test("A file that takes up no space on disk is not a candidate")
    func nothingToFree() {
        #expect(Eligibility.decide(Self.uploaded(), localBytes: 0, now: Self.now) == .skip(.nothingToFree))
    }

    @Test("An empty file outside iCloud is reported as 'outside iCloud'")
    func notICloudWinsOverNothingToFree() {
        let state = Self.uploaded { $0.isUbiquitous = false }
        #expect(Eligibility.decide(state, localBytes: 0, now: Self.now) == .skip(.notICloud))
    }
}
