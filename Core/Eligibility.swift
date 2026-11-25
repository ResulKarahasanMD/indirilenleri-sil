import Foundation

/// Snapshot of the iCloud state of one file or package, read fresh right before a decision.
struct ItemState: Equatable, Sendable {
    enum Download: Equatable, Sendable { case notDownloaded, downloaded, current, unknown }

    var isUbiquitous = false
    var download: Download = .unknown
    var isUploaded = false
    var isUploading = false
    var isDownloading = false
    var hasConflicts = false
    var isExcludedFromSync = false
    var isDataless = false
    /// "Keep Downloaded" on the item or an ancestor: iCloud re-downloads it right after eviction.
    var isPinned = false
    /// Content modification date. Anything can set it, so it may lie in the future.
    var modified: Date?
    /// Inode change date, kept by the kernel: stands in for `modified` when that cannot be trusted.
    var changed: Date?
}

/// Why an item is left alone. Declared in the order reports list them: what the user can do
/// something about first, what is already in the cloud last. The raw values go into the run log.
enum SkipReason: String, CaseIterable, Sendable {
    case uploading = "yukleniyor"
    case notUploaded = "yuklenmedi"
    case recentlyModified = "yeni_degisti"
    case ageUnknown = "tarih_bilinmiyor"
    case conflict = "cakisma"
    case downloading = "iniyor"
    case inUse = "acik_dosya"
    case nonEvictable = "birakilamaz"
    case keepDownloaded = "indirileni_tut"
    case selfDownloadingApp = "kendi_indiren_uygulama"
    case nothingToFree = "yer_kaplamiyor"
    case excludedFromSync = "esitleme_disi"
    case excludedPackage = "paket_haric"
    case notICloud = "icloud_disi"
    case outsideRoots = "izinli_kok_disi"
    case alreadyEvicted = "zaten_birakilmis"

    var label: String {
        switch self {
        case .uploading: "yükleniyor"
        case .notUploaded: "henüz yüklenmedi"
        case .recentlyModified: "son \(Int(Eligibility.minimumAge / 60)) dk'da değişti"
        case .ageUnknown: "değişiklik tarihi okunamadı"
        case .conflict: "çakışmalı"
        case .downloading: "iniyor"
        case .inUse: "açık dosya (kullanımda)"
        case .nonEvictable: "iCloud bırakmaya izin vermiyor"
        case .keepDownloaded: "İndirileni Tut açık"
        case .selfDownloadingApp: "uygulaması kendisi geri indiriyor"
        case .nothingToFree: "diskte yer kaplamıyor"
        case .excludedFromSync: "eşitleme dışı"
        case .excludedPackage: "hariç paket (.app, fotoğraf arşivi…)"
        case .notICloud: "iCloud dışı"
        case .outsideRoots: "izinli konum dışı"
        case .alreadyEvicted: "zaten bırakılmış"
        }
    }
}

enum Decision: Equatable, Sendable {
    case evict
    case skip(SkipReason)
}

enum Eligibility {
    /// Items changed more recently than this are left alone: the upload may not have caught up yet.
    static let minimumAge: TimeInterval = 5 * 60

    /// `localBytes` is what the item occupies on disk right now.
    static func decide(_ s: ItemState, localBytes: Int64, now: Date) -> Decision {
        if s.isDataless { return .skip(.alreadyEvicted) }
        if !s.isUbiquitous { return .skip(.notICloud) }
        if s.isExcludedFromSync { return .skip(.excludedFromSync) }
        if s.isPinned { return .skip(.keepDownloaded) }
        if s.download == .notDownloaded { return .skip(.alreadyEvicted) }
        if localBytes == 0 { return .skip(.nothingToFree) }
        if s.hasConflicts { return .skip(.conflict) }
        if s.isUploading { return .skip(.uploading) }
        if !s.isUploaded { return .skip(.notUploaded) }
        if s.isDownloading { return .skip(.downloading) }
        guard let touched = lastTouched(s, now: now) else { return .skip(.ageUnknown) }
        if now.timeIntervalSince(touched) < minimumAge { return .skip(.recentlyModified) }
        return .evict
    }

    /// When the item last changed, from the first date that can be believed. A modification date in
    /// the future (clock skew, cameras, archives) says nothing about age, so the kernel's change
    /// date takes its place; with neither, the age is unknown and the item is left alone.
    static func lastTouched(_ s: ItemState, now: Date) -> Date? {
        [s.modified, s.changed].compactMap { $0 }.first { $0 <= now }
    }
}
