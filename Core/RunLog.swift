import Foundation
import Synchronization

/// One TSV file per run: `time  action  reason  bytes  path`. Tabs, newlines and backslashes in
/// reasons and file names are escaped so every record stays on one line.
final class RunLog: Sendable {
    enum Action: String, Sendable {
        case evicted
        case skip
        case error
        case stillLocal = "evict_noop"
        case unconfirmed = "evict_unconfirmed"
        case refused
        case missing
        case cloudOnlyFolder = "cloud_only_folder"
    }

    struct Row: Equatable, Sendable {
        var time: String
        var action: String
        var reason: String
        var bytes: Int64
        var path: String
    }

    static let header = "time\taction\treason\tbytes\tpath"

    let url: URL

    private struct Output {
        let handle: FileHandle
        var failure: String?
    }

    private let output: Mutex<Output>

    /// What went wrong the first time a record could not be written; nil while the log is healthy.
    /// After a failure (a full disk, typically) the log stops writing instead of failing on every record.
    var failure: String? { output.withLock { $0.failure } }

    init(url: URL, handle: sending FileHandle) {
        self.url = url
        output = Mutex(Output(handle: handle))
    }

    convenience init(directory: URL, id: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(id).tsv")
        FileManager.default.createFile(atPath: url.path, contents: Data((RunLog.header + "\n").utf8))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.init(url: url, handle: handle)
    }

    deinit { output.withLock { try? $0.handle.close() } }

    func write(_ action: Action, reason: String = "", bytes: Int64 = 0, path: String) {
        let line = [Date().ISO8601Format(), action.rawValue, RunLog.escape(reason), String(bytes), RunLog.escape(path)]
            .joined(separator: "\t") + "\n"
        output.withLock { output in
            guard output.failure == nil else { return }
            do {
                try output.handle.write(contentsOf: Data(line.utf8))
            } catch {
                output.failure = (error as NSError).localizedDescription
            }
        }
    }

    /// Writes down what the scan left alone, and why.
    func record(_ scan: ScanResult) {
        for item in scan.skipped { write(.skip, reason: item.reason.rawValue, bytes: item.bytes, path: item.path) }
        for issue in scan.errors { write(.error, reason: issue.message, path: issue.path) }
        for folder in scan.cloudOnlyFolderPaths { write(.cloudOnlyFolder, path: folder) }
    }

    static func defaultDirectory() -> URL {
        URL(fileURLWithPath: PathPolicy.userHome()).appendingPathComponent("Library/Logs/IndirilenleriSil", isDirectory: true)
    }

    /// The run log written most recently in `directory`.
    static func latest(in directory: URL) -> URL? {
        let logs = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func written(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        return logs.filter { $0.pathExtension == "tsv" }.max { written($0) < written($1) }
    }

    static func newID(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: now) + "_" + String(UUID().uuidString.prefix(6)).lowercased()
    }

    // MARK: - Reading

    static func read(_ url: URL) throws -> [Row] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst().compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5 else { return nil }
            return Row(time: String(fields[0]), action: String(fields[1]), reason: unescape(String(fields[2])),
                       bytes: Int64(fields[3]) ?? 0, path: unescape(String(fields[4])))
        }
    }

    // MARK: - Escaping

    static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "\\": out += "\\\\"
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            default: out.append(character)
            }
        }
        return out
    }

    static func unescape(_ text: String) -> String {
        var out = ""
        var characters = text.makeIterator()
        while let character = characters.next() {
            guard character == "\\", let next = characters.next() else { out.append(character); continue }
            switch next {
            case "t": out.append("\t")
            case "n": out.append("\n")
            case "r": out.append("\r")
            default: out.append(next)
            }
        }
        return out
    }
}
