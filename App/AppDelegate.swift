import AppKit

/// Background (LSUIElement) app. Every trigger becomes a job; jobs run one at a time and the app
/// quits when nothing is left to do.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var queue: [Job] = []
    private var running = false
    /// Alerts on screen that belong to no job: the app must not quit under them.
    private var alertsShown = 0
    private var receivedOpenEvent = false
    private let token = IPC.bundleToken()
    private let policy = PathPolicy()
    private let downloadProtection: Bool
    private let window = JobWindow()

    init(downloadProtection: Bool) {
        self.downloadProtection = downloadProtection
    }

    // MARK: - Triggers

    /// Before the launch ends: a service request that started the app is delivered right after it.
    func applicationWillFinishLaunching(_ note: Notification) {
        NSApp.servicesProvider = self
    }

    /// "İndirilenleri Sil" in Finder's Services menu. See `ServiceRequest`.
    @objc func evictService(_ pasteboard: NSPasteboard, userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        // Measured on macOS 27.2.1: a launch for a service counts as a default launch, and the
        // request arrives before the launch ends. Without this the launch would read Finder's
        // selection as well and run the same job twice.
        receivedOpenEvent = true
        let paths = ServiceRequest.paths(on: pasteboard)
        Log.app.notice("service: \(paths.count, privacy: .public) item(s)")
        guard !paths.isEmpty else {
            error.pointee = "Seçili dosya ya da klasör yok."
            return quitWhenIdle()
        }
        // Finder waits for this call to return: the job, and any alert, start after it.
        Task {
            enqueue(Job(paths: paths, wholeFolder: false))
            quitWhenIdle()
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Notifier.requestAuthorization()
        let isDefaultLaunch = note.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        Log.app.notice("launch default=\(isDefaultLaunch, privacy: .public) openEvent=\(self.receivedOpenEvent, privacy: .public)")
        // Plain launch = click on the ⌘-dragged toolbar icon: act on Finder's selection.
        if isDefaultLaunch && !receivedOpenEvent { enqueue(from: FinderSelection.current) }
        quitWhenIdle()
    }

    /// Requests from the Finder extension, and files dropped on the icon or passed via `open -a`.
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedOpenEvent = true
        for url in urls where !url.isFileURL {
            switch IPC.request(from: url, expectedToken: token) {
            case .evict(let paths): enqueue(Job(paths: paths, wholeFolder: false))
            case .finderSelection: enqueue(from: FinderSelection.current)
            case .finderFolder: enqueue(from: FinderSelection.frontWindowFolder)
            case nil: Log.app.error("url rejected (foreign or bad token)")
            }
        }
        let files = urls.filter(\.isFileURL).map(\.path)
        if !files.isEmpty { enqueue(Job(paths: files, wholeFolder: false)) }
        quitWhenIdle()
    }

    /// Toolbar icon clicked again while a job is still running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        enqueue(from: FinderSelection.current)
        return false
    }

    // MARK: - Queue

    /// Without the download protection nothing is read, not even Finder's selection.
    private var mayRun: Bool {
        if downloadProtection { return true }
        Log.app.fault("download protection unavailable; request refused")
        alert("İndirme koruması kurulamadı",
              "macOS, iCloud'dan indirmeyi engelleyen ayarı kabul etmedi. Yanlışlıkla indirme başlatmamak için hiçbir dosyaya dokunulmadı.")
        return false
    }

    private func enqueue(from read: () -> Result<FinderSelection.Selection, FinderSelection.Failure>) {
        guard mayRun else { return }
        switch read() {
        case .success(let selection) where selection.paths.isEmpty:
            alert("Seçili öğe yok", "Finder'da bir dosya ya da klasör seçip tekrar deneyin.")
        case .success(let selection):
            enqueue(Job(paths: selection.paths, wholeFolder: selection.wholeFolder))
        case .failure(let failure):
            Log.app.error("finder selection could not be read")
            alert("Finder seçimi okunamadı", failure.message)
        }
    }

    private func enqueue(_ job: Job) {
        guard mayRun else { return }
        let places = Set(job.paths.map { policy.location(of: $0).rawValue }).sorted().joined(separator: ", ")
        Log.app.notice("job: \(job.paths.count, privacy: .public) item(s), wholeFolder=\(job.wholeFolder, privacy: .public), in \(places, privacy: .public)")
        queue.append(job)
        pump()
    }

    private func pump() {
        guard !running, !queue.isEmpty else { return }
        running = true
        let job = queue.removeFirst()
        Task {
            await JobRunner(ui: window).run(job)
            running = false
            pump()
            quitWhenIdle()
        }
    }

    private func quitWhenIdle() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !running && queue.isEmpty && alertsShown == 0 { NSApp.terminate(nil) }
        }
    }

    private func alert(_ title: String, _ text: String) {
        alertsShown += 1
        defer {
            alertsShown -= 1
            quitWhenIdle()
        }
        JobWindow.alert(title, text)
    }
}
