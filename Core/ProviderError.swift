import Foundation
import FileProvider

/// Reads the errors `evictUbiquitousItem` throws.
enum ProviderError {
    /// "NSCocoaErrorDomain 512 ← NSFileProviderErrorDomain -1005: …": the localized text alone
    /// ("Dosya kaydedilemedi.") hides the real cause.
    static func describe(_ error: Error) -> String {
        var parts: [String] = []
        var current: NSError? = error as NSError
        while let e = current, parts.count < 4 {
            parts.append("\(e.domain) \(e.code)")
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " ← ") + ": " + (error as NSError).localizedDescription
    }

    /// A refusal is the provider's decision about one item, not a failure of the run.
    static func refusal(_ error: Error) -> SkipReason? {
        var current: NSError? = error as NSError
        while let e = current {
            if e.domain == NSFileProviderErrorDomain, let code = NSFileProviderError.Code(rawValue: e.code) {
                switch code {
                case .nonEvictable, .nonEvictableChildren: return .nonEvictable
                case .unsyncedEdits: return .notUploaded
                default: break
                }
            }
            if e.domain == NSPOSIXErrorDomain, e.code == Int(EBUSY) { return .inUse }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }
}
