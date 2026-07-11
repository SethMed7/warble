import os

/// warble's one logging idiom: the unified log (Console.app, `log stream`), under the app's stable
/// subsystem (the bundle id — plumbing that never changes). Every user-facing failure branch logs a
/// distinguishable `reason=<slug>` from its error taxonomy, so a dogfood failure is diagnosable
/// after the fact:  log stream --predicate 'subsystem == "io.github.sethmed7.voz"'
/// Transcript text is never logged — content stays private even in the local log.
public enum Log {
    public static let dictate = Logger(subsystem: "io.github.sethmed7.voz", category: "dictate")
    public static let speak = Logger(subsystem: "io.github.sethmed7.voz", category: "speak")
}
