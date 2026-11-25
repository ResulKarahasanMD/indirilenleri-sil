import FinderSync
import Foundation
import Testing

/// Finder sends a menu item's action over XPC, on a queue of its own, never on the main thread
/// (crash reports of 2026-09-28: `com.apple.NSXPCConnection.user.endpoint`). An action that
/// insists on the main actor takes the extension down the moment the item is clicked.
@Suite("Finder extension")
struct FinderExtensionTests {
    @Test("The extension stays up when a menu action is called from a background queue",
          arguments: ["evictSelection:", "evictFolder:"])
    func actionSurvivesABackgroundQueue(action: String) async {
        let finished: Bool = await withCheckedContinuation { continuation in
            DispatchQueue(label: "test.finder.xpc").async {
                // The test bundle carries no token, so nothing is sent and no app is opened.
                let finderExtension = FinderSync()
                _ = finderExtension.perform(NSSelectorFromString(action), with: nil)
                continuation.resume(returning: true)
            }
        }
        #expect(finished)
    }

    @Test("The other entry points Finder calls also work on a background queue")
    func entryPointsSurviveABackgroundQueue() async {
        let menus: Int = await withCheckedContinuation { continuation in
            DispatchQueue(label: "test.finder.xpc").async {
                let finderExtension = FinderSync()
                finderExtension.beginObservingDirectory(at: URL(fileURLWithPath: NSTemporaryDirectory()))
                _ = finderExtension.toolbarItemName
                _ = finderExtension.toolbarItemToolTip
                _ = finderExtension.toolbarItemImage
                let kinds: [FIMenuKind] = [.contextualMenuForItems, .contextualMenuForContainer, .toolbarItemMenu]
                continuation.resume(returning: kinds.filter { finderExtension.menu(for: $0) != nil }.count)
            }
        }
        #expect(menus == 3)
    }
}
