import Foundation

/// Human-readable Turkish summaries shared by the command line, the dialogs and the notification.
enum Report {
    /// One line per reason that occurred, in the order `SkipReason` declares them.
    static func skipLines(_ skips: [SkipReason: Tally], cloudOnlyFolders: Int = 0) -> [String] {
        var lines: [String] = []
        for reason in SkipReason.allCases {
            guard let tally = skips[reason], tally.count > 0 else { continue }
            let size = tally.bytes > 0 ? " (\(Fmt.bytes(tally.bytes)))" : ""
            lines.append("\(reason.label): \(Fmt.count(tally.count))\(size)")
        }
        if cloudOnlyFolders > 0 { lines.append("tamamen bulutta klasör: \(Fmt.count(cloudOnlyFolders))") }
        return lines
    }

    static func scan(_ scan: ScanResult) -> String {
        var out = ["taranan dosya/paket: \(Fmt.count(scan.itemsSeen))",
                   "bırakılacak: \(Fmt.count(scan.candidates.count)) · \(Fmt.bytes(scan.candidateBytes))"]
        let skips = skipLines(scan.skips, cloudOnlyFolders: scan.cloudOnlyFolders)
        if !skips.isEmpty { out.append("atlanacak:"); out += skips.map { "  " + $0 } }
        if !scan.errors.isEmpty { out.append("okunamayan: \(Fmt.count(scan.errors.count))") }
        return out.joined(separator: "\n")
    }

    static func evict(_ result: EvictResult) -> String {
        var out = ["bırakıldı: \(Fmt.count(result.evicted.count)) · \(Fmt.bytes(result.evicted.bytes))"]
        func line(_ title: String, _ tally: Tally) {
            if tally.count > 0 { out.append("\(title): \(Fmt.count(tally.count)) · \(Fmt.bytes(tally.bytes))") }
        }
        func section(_ title: String, _ reasons: [SkipReason: Tally]) {
            let lines = skipLines(reasons)
            if !lines.isEmpty { out.append(title + ":"); out += lines.map { "  " + $0 } }
        }
        line("istek yapıldı ama diskte kaldı", result.stillLocal)
        line("istek yapıldı, sonucu beklenmedi", result.unconfirmed)
        line("çalışma sırasında taşınan ya da silinen", result.missing)
        section("iCloud'un reddettiği", result.refused)
        section("taramadan sonra durumu değişip atlanan", result.changed)
        if !result.errors.isEmpty { out.append("hata: \(Fmt.count(result.errors.count)) (ilk: \(result.errors[0].message))") }
        if result.cancelled { out.append("kullanıcı durdurdu") }
        if let failure = result.logFailure { out.append("kayıt tutulamadı: \(failure)") }
        out.append(String(format: "süre: istekler %.1f sn, doğrulama %.1f sn", result.requestSeconds, result.confirmSeconds))
        out.append("boş alan: \(Fmt.bytes(result.spaceBefore.available)) → \(Fmt.bytes(result.spaceAfter.available))"
                   + " (önemli kullanım için: \(Fmt.bytes(result.spaceBefore.important)) → \(Fmt.bytes(result.spaceAfter.important)))")
        return out.joined(separator: "\n")
    }

    /// The result in the two lines a notification has room for.
    static func notification(_ result: EvictResult) -> (title: String, body: String) {
        var body = [String]()
        func mention(_ count: Int, _ what: String) {
            if count > 0 { body.append("\(Fmt.count(count)) \(what)") }
        }
        func total(_ reasons: [SkipReason: Tally]) -> Int { reasons.values.reduce(0) { $0 + $1.count } }
        mention(result.stillLocal.count, "dosya diskte kaldı")
        mention(total(result.refused), "dosyayı iCloud bırakmadı")
        mention(total(result.changed), "dosya son anda değişti")
        mention(result.missing.count, "dosya yerinde yok")
        mention(result.unconfirmed.count, "dosyanın sonucu beklenmedi")
        mention(result.errors.count, "hata")
        if result.cancelled { body.append("durduruldu") }
        if result.logFailure != nil { body.append("kayıt tutulamadı") }
        if body.isEmpty { body.append("\(Fmt.count(result.evicted.count)) dosya artık yalnız iCloud'da") }
        return ("\(Fmt.bytes(result.evicted.bytes)) boşaltıldı", body.joined(separator: " · "))
    }

    /// The line under the progress bar.
    static func progress(_ progress: Progress) -> String {
        switch progress {
        case .scanning(let items, let bytes):
            "\(Fmt.count(items)) dosya tarandı · \(Fmt.bytes(bytes)) bırakılabilir"
        case .waitingForOtherRun:
            "Başka bir çalıştırmanın bitmesi bekleniyor…"
        case .requesting(let done, let total):
            "İstek gönderiliyor: \(Fmt.count(done)) / \(Fmt.count(total))"
        case .confirming(let done, let total, let freed):
            "Doğrulanıyor: \(Fmt.count(done)) / \(Fmt.count(total)) · \(Fmt.bytes(freed)) boşaldı"
        }
    }

    /// "8. DOSYA, 9.İndirilenler ve 3 öğe daha"
    static func names(_ paths: [String]) -> String {
        let names = paths.prefix(3).map { FileManager.default.displayName(atPath: $0) }
        guard paths.count > 3 else { return ListFormatter.localizedString(byJoining: names) }
        return names.prefix(2).joined(separator: ", ") + " ve \(paths.count - 2) öğe daha"
    }
}

enum Fmt {
    static func bytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func count(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }
}
