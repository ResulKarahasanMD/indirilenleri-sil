import AppKit
import Testing

/// The app works in the background: Finder keeps the user's attention while a scan runs. What the
/// app shows has to be on screen without the app being the active one. Measured on the installed
/// app, 2026-09-28: the panel existed for the 7 s of a scan and the window server never drew it.
///
/// The window server is asked, not the window: `NSWindow.isVisible` says yes for a panel that is
/// waiting for its app to become active.
@Suite("İlerleme paneli", .enabled(if: Screen.isInUse, "ekran kilitli ya da uykuda: pencere çizilmez"))
@MainActor
struct ProgressPanelTests {
    init() {
        // What the installed app is (LSUIElement).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    @Test("Uygulama etkin değilken de ekrandadır ve odağı almaz")
    func onScreenWhileTheAppIsInactive() async throws {
        try #require(!NSApplication.shared.isActive)

        let panel = ProgressPanel(title: "Taranıyor…", onStop: {})
        defer { panel.close() }
        panel.show(after: 0)
        try await Task.sleep(for: .milliseconds(400))

        #expect(Screen.shows(window: panel.windowNumber))
        #expect(!NSApplication.shared.isActive)
    }

    @Test("Kapatıldıktan sonra gecikmeli gösterim paneli geri getirmez")
    func staysClosed() async throws {
        let panel = ProgressPanel(title: "Taranıyor…", onStop: {})
        panel.show(after: 0.1)
        panel.close()
        try await Task.sleep(for: .milliseconds(400))

        #expect(!Screen.shows(window: panel.windowNumber))
    }
}

/// The screen as the window server has it.
enum Screen {
    static var isInUse: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        return !locked && CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }

    static func shows(window number: Int) -> Bool {
        let drawn = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return drawn.contains { ($0[kCGWindowNumber as String] as? Int) == number }
    }
}
