import Foundation

/// Command-line mode of the same binary:
///   IndirilenleriSil --dry-run <yol…>     tara, özet yaz (hiçbir şey bırakılmaz)
///   IndirilenleriSil --list <yol…>        tara, aday ve atlanan yolları da yaz
///   IndirilenleriSil --evict <yol…>       tara + bırak, kayıt tut
///   IndirilenleriSil --verify <kayıt|last>  bırakılanlar hâlâ bulutta mı
///
/// Exit status: 0 everything asked for was done; 1 something was left or could not be read;
/// 2 (--verify) evicted items have come back; 64 wrong usage.
enum CLI {
    static func run(_ arguments: [String]) -> Int32 {
        // Like the app: never in the way of what the user is doing.
        pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0)
        let rest = Array(arguments.dropFirst())
        switch arguments.first {
        case "--dry-run": return scan(rest, list: false)
        case "--list": return scan(rest, list: true)
        case "--evict": return evict(rest)
        case "--verify": return verify(rest.first)
        case "--help": usage(); return 0
        default: usage(); return 64
        }
    }

    static func exitStatus(for result: EvictResult, candidates: Int) -> Int32 {
        result.isComplete(of: candidates) && result.logFailure == nil ? 0 : 1
    }

    private static func usage() {
        print("""
        kullanım: IndirilenleriSil --dry-run|--list|--evict <yol…>
                  IndirilenleriSil --verify <kayıt.tsv|last>
        """)
    }

    private static func elapsed(since start: Date) -> String {
        String(format: "%.1f", Date().timeIntervalSince(start))
    }

    private static func scan(_ paths: [String], list: Bool) -> Int32 {
        guard !paths.isEmpty else { usage(); return 64 }
        let start = Date()
        let scan = EvictEngine().scan(paths)
        print(Report.scan(scan))
        print("süre: \(elapsed(since: start)) sn")
        if list {
            for item in scan.candidates { print("aday\t\(item.bytes)\t\(item.isPackage ? "paket" : "dosya")\t\(item.path)") }
            for item in scan.skipped { print("atla\t\(item.bytes)\t\(item.reason.rawValue)\t\(item.path)") }
            for folder in scan.cloudOnlyFolderPaths { print("bulut\t0\tklasör\t\(folder)") }
            for issue in scan.errors { print("hata\t\(issue.message)\t\(issue.path)") }
        }
        return scan.errors.isEmpty ? 0 : 1
    }

    private static func evict(_ paths: [String]) -> Int32 {
        guard !paths.isEmpty else { usage(); return 64 }
        let start = Date()
        let engine = EvictEngine(hooks: EvictEngine.Hooks(progress: { progress in
            if progress == .waitingForOtherRun { print("başka bir çalıştırma sürüyor; bitmesi bekleniyor…") }
        }))
        let scan = engine.scan(paths)
        print(Report.scan(scan))
        let run = engine.run(scan)
        print(Report.evict(run.result))
        print("süre: \(elapsed(since: start)) sn")
        if let log = run.log { print("kayıt: \(log.path)") }
        return exitStatus(for: run.result, candidates: scan.candidates.count)
    }

    private static func verify(_ argument: String?) -> Int32 {
        let chosen = argument == nil || argument == "last"
            ? RunLog.latest(in: RunLog.defaultDirectory())
            : URL(fileURLWithPath: argument!)
        guard let url = chosen else { print("hata: kayıt bulunamadı"); return 1 }
        guard let rows = try? RunLog.read(url) else { print("hata: okunamadı: \(url.path)"); return 1 }
        let result = EvictEngine().verify(rows)
        print("kayıt: \(url.path)")
        print("hâlâ bulutta: \(Fmt.count(result.stillEvicted))")
        print("yeniden inmiş: \(Fmt.count(result.redownloaded.count)) · \(Fmt.bytes(result.redownloaded.reduce(0) { $0 + $1.bytes }))")
        print("yerinde yok (taşınmış/silinmiş): \(Fmt.count(result.missing))")
        for item in result.redownloaded.prefix(50) { print("  inmiş\t\(item.bytes)\t\(item.path)") }
        return result.redownloaded.isEmpty ? 0 : 2
    }
}
