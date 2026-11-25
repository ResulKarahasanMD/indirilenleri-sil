import AppKit

// Before anything touches the file system: this process must never download from iCloud.
let downloadProtection = CloudFiles.preventDownloads()

switch Startup.mode(arguments: Array(CommandLine.arguments.dropFirst()), downloadProtection: downloadProtection) {
case .commandLine(let arguments):
    exit(CLI.run(arguments))

case .refuseCommandLine:
    FileHandle.standardError.write(Data("hata: indirme koruması kurulamadı (setiopolicy_np); hiçbir dosyaya dokunulmadı\n".utf8))
    exit(EX_UNAVAILABLE)

case .app, .refuseApp:
    // The delegate refuses every request when the protection is missing, and says why.
    let delegate = AppDelegate(downloadProtection: downloadProtection)
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
