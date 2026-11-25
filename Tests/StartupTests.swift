import Foundation
import Testing

@Suite("Başlangıç")
struct StartupTests {
    @Test("Komut satırı argümanı komut satırı kipini başlatır")
    func commandLine() {
        #expect(Startup.mode(arguments: ["--dry-run", "/x/y z"], downloadProtection: true)
                == .commandLine(["--dry-run", "/x/y z"]))
    }

    @Test("Argümansız açılış uygulamayı başlatır", arguments: [[String](), ["/Users/u/Desktop/dosya.pdf"]])
    func app(arguments: [String]) {
        #expect(Startup.mode(arguments: arguments, downloadProtection: true) == .app)
    }

    @Test("Sistemin eklediği argümanlar ve değerleri yok sayılır")
    func systemArgumentsAreIgnored() {
        let launched = ["-NSDocumentRevisionsDebugMode", "YES", "-AppleLanguages", "(\"tr-TR\", \"en-TR\")",
                        "-psn_0_123456", "--evict", "/x"]
        #expect(Startup.mode(arguments: launched, downloadProtection: true) == .commandLine(["--evict", "/x"]))
        #expect(Startup.mode(arguments: ["-AppleLanguages", "(tr)", "-psn_0_1"], downloadProtection: true) == .app)
    }

    @Test("İndirme koruması kurulamadıysa hiçbir kip çalışmaz")
    func refusesWithoutDownloadProtection() {
        #expect(Startup.mode(arguments: ["--evict", "/x"], downloadProtection: false) == .refuseCommandLine)
        #expect(Startup.mode(arguments: ["--dry-run", "/x"], downloadProtection: false) == .refuseCommandLine)
        #expect(Startup.mode(arguments: [], downloadProtection: false) == .refuseApp)
    }

    @Test("Yardım, koruma olmadan da gösterilir")
    func helpNeedsNoProtection() {
        #expect(Startup.mode(arguments: ["--help"], downloadProtection: false) == .commandLine(["--help"]))
    }
}
