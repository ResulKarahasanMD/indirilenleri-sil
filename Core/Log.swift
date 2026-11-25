import os

/// Unified-log channels. Read them with
/// `/usr/bin/log show --last 1h --predicate 'subsystem == "com.rak.indirilenlerisil"'`.
///
/// Events are written at `notice`, the lowest level the system keeps on disk; `info` lives in
/// memory only and is gone within hours. They never carry file or folder names, only counts and
/// `PathPolicy.Location` words, so nothing personal ends up in the system log.
enum Log {
    static let app = Logger(subsystem: "com.rak.indirilenlerisil", category: "app")
    static let ext = Logger(subsystem: "com.rak.indirilenlerisil", category: "finder-ext")
}
