import Foundation
import Testing

@Suite("Uzantı → uygulama iletisi")
struct IPCTests {
    @Test("Zor adlı yollar bozulmadan taşınır")
    func evictRequestKeepsAwkwardPaths() throws {
        let paths = [
            "/Users/u/Library/Mobile Documents/com~apple~CloudDocs/8. DOSYA",
            "/Users/u/Desktop/a&b=c+d #1 ?%20.txt",
            "/Users/u/Desktop/9.I\u{0307}ndirilenler/Ğüşıöç çift  boşluk",
            "/Users/u/Desktop/tab\there",
            "/Users/u/Desktop/satır\nsonu",
        ]
        let url = try #require(IPC.url(for: .evict(paths), token: "abc123"))
        #expect(url.scheme == "indirilenlerisil")
        #expect(IPC.request(from: url, expectedToken: "abc123") == .evict(paths))
    }

    @Test("Yol taşımayan istekler türünü korur", arguments: [IPC.Request.finderSelection, .finderFolder])
    func pathlessRequestsRoundTrip(request: IPC.Request) throws {
        let url = try #require(IPC.url(for: request, token: "abc123"))
        #expect(IPC.request(from: url, expectedToken: "abc123") == request)
    }

    @Test("Yanlış token'lı istek reddedilir", arguments: [IPC.Request.evict(["/a"]), .finderSelection, .finderFolder])
    func wrongTokenIsRejected(request: IPC.Request) throws {
        let url = try #require(IPC.url(for: request, token: "good"))
        #expect(IPC.request(from: url, expectedToken: "bad") == nil)
        #expect(IPC.request(from: url, expectedToken: "") == nil)
    }

    @Test("Yabancı ya da bozuk URL reddedilir", arguments: [
        "indirilenlerisil://evict?p=/a",
        "indirilenlerisil://finder-selection",
        "indirilenlerisil://other?t=good&p=/a",
        "indirilenlerisil://evict?t=good&p=relative",
        "indirilenlerisil://evict?t=good",
        "baska://evict?t=good&p=/a",
    ])
    func rejected(url: String) throws {
        #expect(IPC.request(from: try #require(URL(string: url)), expectedToken: "good") == nil)
    }

    @Test("Yolsuz bırakma isteği ve boş token URL üretmez")
    func nothingToSend() {
        #expect(IPC.url(for: .evict([]), token: "good") == nil)
        #expect(IPC.url(for: .evict(["/a"]), token: "") == nil)
        #expect(IPC.url(for: .finderFolder, token: "") == nil)
    }
}
