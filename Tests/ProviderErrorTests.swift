import Foundation
import Testing

@Suite("iCloud error decoding")
struct ProviderErrorTests {
    static func wrapped(_ domain: String, _ code: Int) -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: 512,
                userInfo: [NSUnderlyingErrorKey: NSError(domain: domain, code: code)])
    }

    @Test("The underlying error chain appears in the description")
    func underlyingChainIsKept() {
        let text = ProviderError.describe(Self.wrapped("NSFileProviderErrorDomain", -1005))
        #expect(text.hasPrefix("NSCocoaErrorDomain 512 ← NSFileProviderErrorDomain -1005: "))
    }

    @Test("An iCloud refusal is a skip reason, not an error")
    func refusalsBecomeSkipReasons() {
        #expect(ProviderError.refusal(Self.wrapped("NSFileProviderErrorDomain", -2008)) == .nonEvictable)
        #expect(ProviderError.refusal(Self.wrapped("NSFileProviderErrorDomain", -2007)) == .notUploaded)
        #expect(ProviderError.refusal(Self.wrapped(NSPOSIXErrorDomain, Int(EBUSY))) == .inUse)
    }

    @Test("An unrecognized error is not turned into a skip reason")
    func unknownErrorsStayErrors() {
        #expect(ProviderError.refusal(Self.wrapped("NSFileProviderErrorDomain", -1005)) == nil)
        #expect(ProviderError.refusal(NSError(domain: NSCocoaErrorDomain, code: 4)) == nil)
    }
}
