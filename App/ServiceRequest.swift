import AppKit

/// "İndirilenleri Sil" in Finder's Services menu: the way in from the context menu.
///
/// Measured on macOS 27.2.1: Finder asks no third-party Finder Sync extension for a context menu
/// on items in iCloud Drive, and Desktop and Documents belong to it while they sync. An extension
/// that watched `/` got the request for a local folder and none for those. Services do not pass
/// through Finder Sync.
enum ServiceRequest {
    /// `NSMessage` in Info.plist. AppKit calls `<message>:userData:error:` on the services provider.
    static let message = "evictService"
    static var selector: Selector { NSSelectorFromString("\(message):userData:error:") }

    /// The items Finder put on the pasteboard, as absolute paths.
    static func paths(on pasteboard: NSPasteboard) -> [String] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        // Finder may hand over file reference URLs (`/.file/id=…`): the engine wants paths.
        return urls.compactMap { $0.filePathURL?.path }
    }
}
