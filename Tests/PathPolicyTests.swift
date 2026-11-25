import Foundation
import Testing

@Suite("Allowed locations")
struct PathPolicyTests {
    let policy = PathPolicy(home: "/Users/u", resolve: { $0 })
    let cloudDocs = "/Users/u/Library/Mobile Documents/com~apple~CloudDocs"
    let mobileDocuments = "/Users/u/Library/Mobile Documents"

    @Test("iCloud Drive, Desktop, Documents and app folders are allowed")
    func allowedRoots() {
        #expect(policy.root(containing: cloudDocs + "/8. DOSYA/a.mp3") == cloudDocs)
        #expect(policy.root(containing: cloudDocs) == cloudDocs)
        #expect(policy.root(containing: "/Users/u/Desktop/x") == "/Users/u/Desktop")
        #expect(policy.root(containing: "/Users/u/Documents") == "/Users/u/Documents")
        let pages = mobileDocuments + "/com~apple~Pages/Documents"
        #expect(policy.root(containing: pages + "/Rapor.pages") == pages)
    }

    @Test("App-private data and other locations are rejected", arguments: [
        "/Users/u/Library/Mobile Documents/net~whatsapp~WhatsApp/Accounts/db",
        "/Users/u/Library/Mobile Documents/com~apple~Pages/Data/x",
        "/Users/u/Library/Mobile Documents",
        "/Users/u/Library/Mobile Documents/com~apple~CloudDocsX/a",
        "/Users/u/DesktopOld/a",
        "/Users/u/Downloads/a",
        "/Users/other/Desktop/a",
    ])
    func rejected(path: String) {
        #expect(policy.root(containing: path) == nil)
    }

    @Test("The Notability folder is recognized whatever its team ID")
    func selfDownloadingContainers() {
        #expect(policy.isSelfDownloadingContainer(mobileDocuments + "/ZP9ZJ4EF3S~com~gingerlabs~Notability/Documents/Not.nbn"))
        #expect(policy.isSelfDownloadingContainer(mobileDocuments + "/ABCDE12345~com~gingerlabs~Notability/Documents"))
        #expect(!policy.isSelfDownloadingContainer(cloudDocs + "/Notability/Not.nbn"))
        #expect(!policy.isSelfDownloadingContainer(mobileDocuments + "/com~apple~Pages/Documents/Rapor.pages"))
        #expect(!policy.isSelfDownloadingContainer("/Users/u/Documents/com~gingerlabs~Notability/x"))
    }

    @Test("Finder metadata and legacy placeholders are ignored")
    func ignoredNames() {
        #expect(PathPolicy.isIgnoredName(".DS_Store"))
        #expect(PathPolicy.isIgnoredName("Icon\r"))
        #expect(PathPolicy.isIgnoredName(".rapor.pdf.icloud"))
        #expect(!PathPolicy.isIgnoredName("rapor.icloud"))
        #expect(!PathPolicy.isIgnoredName("Icon"))
        #expect(PathPolicy.isIgnoredDirectory(".Trash"))
    }

    @Test("Live databases and app packages are excluded")
    func excludedPackages() {
        #expect(PathPolicy.isExcludedPackage("Fotoğraflar.photoslibrary"))
        #expect(PathPolicy.isExcludedPackage("X.APP"))
        #expect(!PathPolicy.isExcludedPackage("Rapor.pages"))
    }

    @Test("A location is described by a word that contains no names", arguments: [
        ("/Users/u/Library/Mobile Documents/com~apple~CloudDocs/Hasta Adı Soyadı/rapor.pdf", "iCloud Drive"),
        ("/Users/u/Library/Mobile Documents/com~apple~CloudDocs", "iCloud Drive"),
        ("/Users/u/Desktop/gizli klasör", "Masaüstü"),
        ("/Users/u/Documents/a/b/c.txt", "Belgeler"),
        ("/Users/u/Library/Mobile Documents/com~apple~Pages/Documents/Rapor.pages", "uygulama klasörü"),
        ("/Users/u/Downloads/x", "izinli konum dışı"),
        ("/Users/u/Library/Mobile Documents/com~apple~Pages/Data/x", "izinli konum dışı"),
    ])
    func locationIsDescribedWithoutNames(path: String, expected: String) {
        #expect(policy.location(of: path).rawValue == expected)
    }

    @Test("The extension watches folders that cover every allowed location", arguments: [
        "/Users/u/Library/Mobile Documents/com~apple~CloudDocs/8. DOSYA",
        "/Users/u/Desktop/x",
        "/Users/u/Documents/y/z",
        "/Users/u/Library/Mobile Documents/com~apple~Pages/Documents/Rapor.pages",
    ])
    func everyAllowedRootIsMonitored(path: String) {
        #expect(policy.root(containing: path) != nil)
        #expect(policy.finderSyncDirectories.contains { path.hasPrefix($0 + "/") })
    }
}
