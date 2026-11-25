import Foundation
import Testing

@Suite("İndirileni Tut işareti")
struct PinTests {
    let home: TempHome

    init() throws { home = try TempHome() }

    func mark(_ path: String) {
        let one: [UInt8] = [1]
        #expect(setxattr(path, PinCache.marker, one, 1, 0, 0) == 0)
    }

    @Test("Öğenin kendisindeki işaret sayılır")
    func markerOnTheItem() throws {
        let marked = try home.file("Desktop/serbest/c.bin")
        let plain = try home.file("Desktop/serbest/b.bin")
        mark(marked)

        let pins = PinCache()
        #expect(pins.isPinned(marked, inside: home.path))
        #expect(!pins.isPinned(plain, inside: home.path))
    }

    @Test("Üst klasördeki işaret içindekilere geçer")
    func markerOnAnAncestor() throws {
        let inside = try home.file("Desktop/tut/alt/daha alt/a.bin")
        let sibling = try home.file("Desktop/tut/alt/b.bin")
        let outside = try home.file("Desktop/serbest/c.bin")
        mark(home.desktop + "/tut")

        let pins = PinCache()
        #expect(pins.isPinned(inside, inside: home.path))
        #expect(pins.isPinned(sibling, inside: home.path))
        #expect(!pins.isPinned(outside, inside: home.path))
    }

    @Test("Sınırın dışındaki klasörlere bakılmaz")
    func ancestorsOutsideTheBoundaryAreNotConsulted() throws {
        // "ev" is the boundary; "evim" only shares its first letters.
        let boundary = try home.folder("Desktop/ev")
        let lookalike = try home.file("Desktop/evim/tut/a.bin")
        let above = try home.file("Desktop/ev/b.bin")
        mark(home.desktop + "/evim/tut")
        mark(home.desktop)

        let pins = PinCache()
        #expect(!pins.isPinned(lookalike, inside: boundary))
        #expect(!pins.isPinned(above, inside: boundary))
    }
}
