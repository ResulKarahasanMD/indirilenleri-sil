import Foundation

/// A throwaway home folder with Desktop, Documents and iCloud Drive inside; removed when released.
final class TempHome {
    let path: String

    init() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = PathPolicy.realpathResolve(url.path) ?? url.path
        for folder in ["Desktop", "Documents", "Downloads", "Library/Mobile Documents/com~apple~CloudDocs"] {
            try FileManager.default.createDirectory(atPath: path + "/" + folder, withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(atPath: path) }

    var policy: PathPolicy { PathPolicy(home: path) }
    var desktop: String { path + "/Desktop" }
    var cloudDocs: String { path + "/Library/Mobile Documents/com~apple~CloudDocs" }

    /// Creates a file (and the folders above it) and returns its path. `relative` starts at the home folder.
    @discardableResult
    func file(_ relative: String, bytes: Int = 1) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: full, contents: Data(count: bytes))
        return full
    }

    @discardableResult
    func folder(_ relative: String) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }
}
