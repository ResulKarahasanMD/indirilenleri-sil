import AppKit

/// Shows a job to the user: a progress panel while it works, alerts for its questions, a
/// notification for its result.
@MainActor
final class JobWindow: JobUI {
    private var panel: ProgressPanel?

    func begin(_ phase: JobPhase, stop: CancelFlag) {
        let panel = ProgressPanel(title: phase == .scanning ? "Taranıyor…" : "İndirilenler siliniyor…",
                                  onStop: { stop.set() })
        // Only work that takes a moment gets a panel.
        panel.show(after: phase == .scanning ? 0.8 : 0.5)
        self.panel = panel
    }

    func show(_ progress: Progress) {
        panel?.show(progress)
    }

    func end() {
        panel?.close()
        panel = nil
    }

    func nothingToEvict(_ scan: ScanResult, for job: Job) {
        Log.app.notice("scan: \(scan.itemsSeen, privacy: .public) seen, nothing to evict, \(scan.errors.count, privacy: .public) unreadable")
        Self.alert("Boşaltılacak yerel kopya yok", summary(of: scan, for: job).joined(separator: "\n"))
    }

    func confirm(_ scan: ScanResult, for job: Job) -> Bool {
        Log.app.notice("scan: \(scan.itemsSeen, privacy: .public) seen, \(scan.candidates.count, privacy: .public) candidates, \(scan.candidateBytes, privacy: .public) bytes")
        let alert = NSAlert()
        alert.messageText = "\(Fmt.count(scan.candidates.count)) öğenin yerel kopyası silinsin mi? (\(Fmt.bytes(scan.candidateBytes)))"
        alert.informativeText = (summary(of: scan, for: job) + ["", "Dosyalar iCloud'da kalır; açtığınızda yeniden iner."])
            .joined(separator: "\n")
        alert.addButton(withTitle: "İndirilenleri Sil")
        alert.addButton(withTitle: "Vazgeç")
        alert.icon = NSImage(systemSymbolName: "icloud.slash", accessibilityDescription: nil)
        NSApp.activate()
        Presentation.log(alert.window, as: "confirm")
        let agreed = alert.runModal() == .alertFirstButtonReturn
        Log.app.notice("confirm: \(agreed ? "yes" : "no", privacy: .public)")
        return agreed
    }

    func finished(_ result: EvictResult, log: URL?) async {
        Log.app.notice("""
            evict: \(result.evicted.count, privacy: .public) evicted, \(result.evicted.bytes, privacy: .public) bytes, \
            stillLocal \(result.stillLocal.count, privacy: .public), refused \(result.refused.values.reduce(0) { $0 + $1.count }, privacy: .public), \
            changed \(result.changed.values.reduce(0) { $0 + $1.count }, privacy: .public), missing \(result.missing.count, privacy: .public), \
            errors \(result.errors.count, privacy: .public), cancelled \(result.cancelled, privacy: .public), \
            logged \(result.logFailure == nil, privacy: .public)
            """)
        let message = Report.notification(result)
        await Notifier.post(title: message.title, body: message.body, log: log)
    }

    private func summary(of scan: ScanResult, for job: Job) -> [String] {
        var lines = [(job.wholeFolder ? "Seçim yok, klasörün tamamı: " : "Seçim: ") + Report.names(scan.inputs), ""]
        let skips = Report.skipLines(scan.skips, cloudOnlyFolders: scan.cloudOnlyFolders)
        if !skips.isEmpty { lines.append("Atlanacak (dokunulmaz):"); lines += skips.map { "• " + $0 } }
        if !scan.errors.isEmpty { lines.append("• okunamayan: \(Fmt.count(scan.errors.count)) (izinleri denetleyin)") }
        return lines
    }

    static func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        Presentation.log(alert.window, as: "alert")
        alert.runModal()
    }
}

/// What the user could see of a window shortly after it was shown, for the log. The app runs in
/// the background, and afterwards nobody can tell whether a question was in view.
@MainActor
enum Presentation {
    /// A timer of the run loop, not a task: a question is asked from inside a job of the main
    /// actor, and until it is answered the main actor starts nothing else (measured 2026-09-28:
    /// a task set up before `runModal` had not run 9 s into the dialog).
    static func log(_ window: NSWindow, as what: String) {
        let timer = Timer(timeInterval: 0.7, repeats: false) { _ in
            MainActor.assumeIsolated {
                // Already answered or closed: nothing to tell.
                guard window.isVisible else { return }
                Log.app.notice("""
                    \(what, privacy: .public) shown: drawn=\(window.occlusionState.contains(.visible), privacy: .public), \
                    activeSpace=\(window.isOnActiveSpace, privacy: .public), level=\(window.level.rawValue, privacy: .public), \
                    appActive=\(NSApplication.shared.isActive, privacy: .public)
                    """)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

/// Small floating panel with a status line, a progress bar and a stop button. It shows while the
/// app is in the background and takes nobody's focus: Finder stays the active app during a scan.
@MainActor
final class ProgressPanel: NSObject {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let onStop: () -> Void
    private var closed = false

    init(title: String, onStop: @escaping () -> Void) {
        self.onStop = onStop
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 110),
                        styleMask: [.titled, .utilityWindow], backing: .buffered, defer: true)
        super.init()
        panel.title = title
        panel.level = .floating
        // A panel leaves the screen while its app is inactive, and this app usually is.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        bar.isIndeterminate = true
        bar.style = .bar
        let stop = NSButton(title: "Durdur", target: self, action: #selector(stopTapped))
        let stack = NSStackView(views: [label, bar, stop])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        bar.widthAnchor.constraint(equalToConstant: 348).isActive = true
        panel.contentView = stack
        label.stringValue = title
    }

    /// The window server's name for the panel.
    var windowNumber: Int { panel.windowNumber }

    func show(after delay: TimeInterval) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !closed else { return }
            bar.startAnimation(nil)
            panel.center()
            panel.orderFrontRegardless()
            Presentation.log(panel, as: "progress")
        }
    }

    func show(_ progress: Progress) {
        label.stringValue = Report.progress(progress)
        guard let fraction = progress.fraction else { return }
        bar.isIndeterminate = false
        // Never backwards, whatever order reports arrive in.
        bar.doubleValue = max(bar.doubleValue, fraction * 100)
    }

    func close() {
        closed = true
        panel.orderOut(nil)
    }

    @objc private func stopTapped() {
        label.stringValue = "Durduruluyor…"
        onStop()
    }
}
