import Foundation

/// Finder extension → host app hand-off over the custom URL scheme:
/// `indirilenlerisil://evict?t=<token>&p=<path>&p=<path>…`, `…://finder-selection?t=<token>`,
/// `…://finder-folder?t=<token>`.
///
/// Any app or web page can open a registered scheme, so a request only counts when it carries the
/// token that both Info.plists share. The token lives in the app bundle, where every local process
/// can read it: it keeps stray and remote URLs out, it is not authentication. A request can do no
/// more than start a scan that the user still has to confirm.
enum IPC {
    /// What the Finder extension asks the host app to do.
    enum Request: Equatable, Sendable {
        /// Evict these items.
        case evict([String])
        /// Finder gave the extension no selection: read it from Finder.
        case finderSelection
        /// Finder gave the extension no folder: use the one in the front Finder window.
        case finderFolder

        fileprivate var host: String {
            switch self {
            case .evict: "evict"
            case .finderSelection: "finder-selection"
            case .finderFolder: "finder-folder"
            }
        }
    }

    static let scheme = "indirilenlerisil"
    static let tokenKey = "ISToken"

    private static let unreserved = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    static func url(for request: Request, token: String) -> URL? {
        guard !token.isEmpty else { return nil }
        var paths: [String] = []
        if case .evict(let items) = request {
            guard !items.isEmpty else { return nil }
            paths = items
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = request.host
        components.percentEncodedQueryItems = [URLQueryItem(name: "t", value: encode(token))]
            + paths.map { URLQueryItem(name: "p", value: encode($0)) }
        return components.url
    }

    /// The request `url` carries, or nil when the URL is foreign, malformed or has the wrong token.
    static func request(from url: URL, expectedToken: String) -> Request? {
        guard !expectedToken.isEmpty, url.scheme == scheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "t" })?.value == expectedToken else { return nil }
        switch url.host {
        case Request.finderSelection.host: return .finderSelection
        case Request.finderFolder.host: return .finderFolder
        case Request.evict([]).host:
            let paths = items.filter { $0.name == "p" }.compactMap(\.value).filter { $0.hasPrefix("/") }
            return paths.isEmpty ? nil : .evict(paths)
        default: return nil
        }
    }

    static func bundleToken() -> String {
        Bundle.main.object(forInfoDictionaryKey: tokenKey) as? String ?? ""
    }
}
