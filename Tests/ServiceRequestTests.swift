import AppKit
import Testing

/// The Services entry is wired by name: Info.plist names a message, AppKit builds a selector from
/// it and calls the services provider. A name that drifts fails silently: the menu item stays and
/// does nothing.
@Suite("Servis")
struct ServiceRequestTests {
    private static let infoPlist = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Info.plist")

    private func services() throws -> [[String: Any]] {
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: Self.infoPlist), format: nil)
        return (plist as? [String: Any])?["NSServices"] as? [[String: Any]] ?? []
    }

    @Test("Info.plist'teki servis, uygulamanın yanıt verdiği iletiyi adlandırır")
    @MainActor func messageMatchesTheDelegate() throws {
        let service = try #require(try services().first)
        #expect(try services().count == 1)
        #expect(service["NSMessage"] as? String == ServiceRequest.message)
        #expect(AppDelegate(downloadProtection: true).responds(to: ServiceRequest.selector))
    }

    @Test("Servis her dosya ve klasör için, yalnız Finder'da sunulur")
    func offeredForEveryItemInFinder() throws {
        let service = try #require(try services().first)
        #expect(service["NSSendFileTypes"] as? [String] == ["public.item"])
        #expect((service["NSMenuItem"] as? [String: String])?["default"] == "İndirilenleri Sil")
        // Without NSRequiredContext macOS leaves a new service switched off.
        #expect((service["NSRequiredContext"] as? [String: String])?["NSApplicationIdentifier"] == "com.apple.finder")
    }

    @Test("Panodaki dosya URL'leri yola çevrilir, dosya olmayanlar atlanır")
    func pathsFromThePasteboard() throws {
        let home = try TempHome()
        let file = URL(fileURLWithPath: try home.file("Desktop/a b.txt"))
        let folder = URL(fileURLWithPath: try home.folder("Desktop/klasör"), isDirectory: true)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([file as NSURL, folder as NSURL, URL(string: "https://example.com")! as NSURL]))

        #expect(ServiceRequest.paths(on: pasteboard) == [file.path, folder.path])
    }

    @Test("Boş panodan yol çıkmaz")
    func emptyPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(ServiceRequest.paths(on: pasteboard).isEmpty)
    }
}
