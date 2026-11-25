import Foundation
import CoreServices

/// Reads what Finder has selected, over Apple Events (needs the Automation permission for Finder).
enum FinderSelection {
    struct Selection: Equatable {
        var paths: [String]
        /// Nothing was selected: the paths are the folder the window shows.
        var wholeFolder: Bool
    }

    struct Failure: Error {
        let message: String
    }

    /// Both scripts answer with a list: a "0"/"1" flag for `wholeFolder`, then the paths. A list,
    /// not text joined by line breaks, because a file name may contain a line break too.
    private static let selectionScript = """
    tell application "Finder"
        set chosen to selection as alias list
        set wholeFolder to "0"
        if (count of chosen) is 0 then
            try
                set chosen to {(target of front Finder window) as alias}
                set wholeFolder to "1"
            end try
        end if
        set answer to {wholeFolder}
        repeat with one in chosen
            set end of answer to POSIX path of (contents of one)
        end repeat
        return answer
    end tell
    """

    /// No window, or one that shows no folder (Recents, AirDrop, a search): no paths.
    private static let folderScript = """
    tell application "Finder"
        try
            return {"1", POSIX path of ((target of front Finder window) as alias)}
        end try
        return {"1"}
    end tell
    """

    /// The selection; with nothing selected, the folder shown in the front Finder window.
    @MainActor
    static func current() -> Result<Selection, Failure> {
        ask(selectionScript)
    }

    /// The folder shown in the front Finder window, whatever is selected in it.
    @MainActor
    static func frontWindowFolder() -> Result<Selection, Failure> {
        ask(folderScript)
    }

    @MainActor
    private static func ask(_ source: String) -> Result<Selection, Failure> {
        var error: NSDictionary?
        guard let answer = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
            let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
            if code == errAEEventNotPermitted {
                return .failure(Failure(message: "Finder'ı denetleme izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Otomasyon › İndirilenleri Sil altında Finder'ı açın."))
            }
            let text = error?[NSAppleScript.errorMessage] as? String ?? "bilinmeyen hata"
            return .failure(Failure(message: "\(text) (\(code))"))
        }
        let count = answer.numberOfItems
        let items = count > 0 ? (1...count).compactMap { answer.atIndex($0)?.stringValue } : []
        guard let selection = selection(from: items) else {
            return .failure(Failure(message: "Finder beklenmeyen bir yanıt verdi."))
        }
        return .success(selection)
    }

    /// What Finder answered, as the scripts return it: a "0"/"1" flag for `wholeFolder`, then the paths.
    static func selection(from items: [String]) -> Selection? {
        guard let flag = items.first, flag == "0" || flag == "1" else { return nil }
        let paths = items.dropFirst().filter { !$0.isEmpty }.map { path in
            path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return Selection(paths: paths, wholeFolder: flag == "1")
    }
}
