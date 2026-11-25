import Cocoa
import FinderSync

/// Adds "İndirilenleri Sil" to Finder's toolbar for iCloud Drive locations, and to the context menu
/// where Finder lets it. It never touches files itself: it hands the request to the host app over
/// the URL scheme.
///
/// Measured on macOS 26.6.2: Finder never calls beginObservingDirectory for iCloud Drive
/// (~/Library/Mobile Documents/…), even when those paths are listed explicitly. There the context
/// menu does not appear, and while the toolbar menu is being built Finder hands over neither
/// selection nor folder. The toolbar items work all the same: what Finder does not give the
/// extension, the host app reads from Finder itself.
///
/// Measured on macOS 27.2.1, Desktop and Documents syncing to iCloud: the context menu does not
/// appear there either (it did on 26.6.2). Finder never asks for it: no `menu(for:)` call with a
/// contextual kind, also not for an extension that watches `/`, which is asked for a local folder.
/// From the context menu the way in is the app's entry under Services: see `ServiceRequest`.
final class FinderSync: FIFinderSync {
    private let policy = PathPolicy()

    override init() {
        super.init()
        let folders = policy.finderSyncDirectories.map { URL(fileURLWithPath: $0, isDirectory: true) }
        FIFinderSyncController.default().directoryURLs = Set(folders)
        Log.ext.notice("init; watching \(folders.count, privacy: .public) folders")
    }

    override func beginObservingDirectory(at url: URL) {
        Log.ext.notice("observing \(self.policy.location(of: url.path).rawValue, privacy: .public)")
    }

    // MARK: - Toolbar

    override var toolbarItemName: String { "İndirilenleri Sil" }
    override var toolbarItemToolTip: String { "iCloud'a yüklenmiş dosyaların yerel kopyalarını diskten kaldırır" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "icloud.slash", accessibilityDescription: "İndirilenleri Sil") ?? NSImage()
    }

    // MARK: - Menus

    override func menu(for kind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let selected = controller.selectedItemURLs()?.count ?? 0
        let target = controller.targetedURL().map { policy.location(of: $0.path).rawValue } ?? "yok"
        Log.ext.notice("menu kind=\(kind.rawValue, privacy: .public) selected=\(selected, privacy: .public) target=\(target, privacy: .public)")

        let menu = NSMenu(title: "")
        switch kind {
        case .contextualMenuForItems:
            menu.addItem(item("İndirilenleri Sil", #selector(evictSelection(_:))))
        case .contextualMenuForContainer:
            menu.addItem(item("Bu Klasörün İndirilenlerini Sil", #selector(evictFolder(_:))))
        case .toolbarItemMenu:
            menu.addItem(item("Seçilenlerin İndirilenlerini Sil", #selector(evictSelection(_:))))
            menu.addItem(item("Bu Klasörün İndirilenlerini Sil", #selector(evictFolder(_:))))
        default:
            return nil
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "icloud.slash", accessibilityDescription: nil)
        return item
    }

    // MARK: - Actions
    //
    // Finder sends these over XPC, on a queue of its own, never on the main thread. `@IBAction`
    // would tie them to the main actor, and in Swift 6 the process is stopped on entry when the
    // caller is somewhere else (crash reports of 2026-09-28). So they are plain `@objc` and
    // isolated to nothing. Finder is asked for the selection again here: the state of the menu
    // item does not survive the hand-off.

    @objc nonisolated func evictSelection(_ sender: AnyObject?) {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        send(selected.isEmpty ? .finderSelection : .evict(selected.map(\.path)))
    }

    @objc nonisolated func evictFolder(_ sender: AnyObject?) {
        let folder = FIFinderSyncController.default().targetedURL()
        send(folder.map { .evict([$0.path]) } ?? .finderFolder)
    }

    private nonisolated func send(_ request: IPC.Request) {
        guard let url = IPC.url(for: request, token: IPC.bundleToken()) else {
            Log.ext.error("request could not be built (no token?)")
            return
        }
        let kind = switch request {
        case .evict(let paths): "evict \(paths.count)"
        case .finderSelection: "finder-selection"
        case .finderFolder: "finder-folder"
        }
        Log.ext.notice("sending \(kind, privacy: .public)")
        // The host has to come to the front: its first act is to ask the user a question.
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Log.ext.error("host could not be opened: \((error as NSError).code, privacy: .public)") }
        }
    }
}
