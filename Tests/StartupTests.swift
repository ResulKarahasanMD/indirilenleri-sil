import Foundation
import Testing

@Suite("Startup")
struct StartupTests {
    @Test("A command-line argument starts command-line mode")
    func commandLine() {
        #expect(Startup.mode(arguments: ["--dry-run", "/x/y z"], downloadProtection: true)
                == .commandLine(["--dry-run", "/x/y z"]))
    }

    @Test("Launching without arguments starts the app", arguments: [[String](), ["/Users/u/Desktop/dosya.pdf"]])
    func app(arguments: [String]) {
        #expect(Startup.mode(arguments: arguments, downloadProtection: true) == .app)
    }

    @Test("Arguments the system adds, and their values, are ignored")
    func systemArgumentsAreIgnored() {
        let launched = ["-NSDocumentRevisionsDebugMode", "YES", "-AppleLanguages", "(\"tr-TR\", \"en-TR\")",
                        "-psn_0_123456", "--evict", "/x"]
        #expect(Startup.mode(arguments: launched, downloadProtection: true) == .commandLine(["--evict", "/x"]))
        #expect(Startup.mode(arguments: ["-AppleLanguages", "(tr)", "-psn_0_1"], downloadProtection: true) == .app)
    }

    @Test("If download protection could not be set up, no mode runs")
    func refusesWithoutDownloadProtection() {
        #expect(Startup.mode(arguments: ["--evict", "/x"], downloadProtection: false) == .refuseCommandLine)
        #expect(Startup.mode(arguments: ["--dry-run", "/x"], downloadProtection: false) == .refuseCommandLine)
        #expect(Startup.mode(arguments: [], downloadProtection: false) == .refuseApp)
    }

    @Test("Help is shown even without download protection")
    func helpNeedsNoProtection() {
        #expect(Startup.mode(arguments: ["--help"], downloadProtection: false) == .commandLine(["--help"]))
    }
}
