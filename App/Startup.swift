import Foundation

/// Decides, from the command line and the state of the download protection, what this launch is.
enum Startup {
    enum Mode: Equatable {
        case commandLine([String])
        case app
        /// The download protection could not be set up: refuse to touch anything.
        case refuseCommandLine
        case refuseApp
    }

    static func mode(arguments: [String], downloadProtection: Bool) -> Mode {
        let arguments = userArguments(arguments)
        guard let command = arguments.first, command.hasPrefix("--") else {
            return downloadProtection ? .app : .refuseApp
        }
        // Help touches no file.
        return downloadProtection || command == "--help" ? .commandLine(arguments) : .refuseCommandLine
    }

    /// What the user typed. Launch Services and AppKit add arguments of their own: `-psn_…`, and
    /// defaults overrides such as `-AppleLanguages (tr)` whose value follows as the next argument.
    static func userArguments(_ arguments: [String]) -> [String] {
        var kept: [String] = []
        var valueFollows = false
        for argument in arguments {
            let isValue = valueFollows && !argument.hasPrefix("-")
            valueFollows = argument.hasPrefix("-NS") || argument.hasPrefix("-Apple")
            if isValue || valueFollows || argument.hasPrefix("-psn_") { continue }
            kept.append(argument)
        }
        return kept
    }
}
