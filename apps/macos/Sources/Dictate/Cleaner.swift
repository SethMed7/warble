import Foundation

/// Cleanup engines are pluggable so a local-LLM cleaner (e.g. Ollama) can
/// slot in later — any future engine must stay on-device; see README.
protocol Cleaner {
    func clean(_ raw: String) -> String
}

/// Zero-setup fallback: the built-in Swift port of clean.ts.
struct BasicSwiftCleaner: Cleaner {
    func clean(_ raw: String) -> String { BasicCleaner.cleaned(raw) }
}

/// Canonical cleaner: the TypeScript helper in ~/.dictado, run by bun with
/// raw text on stdin and cleaned text on stdout. Any failure or a >2s stall
/// falls back to BasicCleaner — same rules, so behavior is identical.
final class BunCleaner: Cleaner {
    private static let helperDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dictado")

    static func bunPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.bun/bin/bun", "/opt/homebrew/bin/bun", "/usr/local/bin/bun"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func isAvailable() -> Bool {
        bunPath() != nil && FileManager.default.fileExists(
            atPath: helperDir.appendingPathComponent("clean.ts").path)
    }

    /// Blocks up to 2s — call off the main thread.
    func clean(_ raw: String) -> String {
        guard let bun = Self.bunPath() else { return BasicCleaner.cleaned(raw) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bun)
        p.arguments = ["run", "clean.ts"]
        p.currentDirectoryURL = Self.helperDir
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = Pipe()

        do {
            try p.run()
            stdin.fileHandleForWriting.write(Data(raw.utf8))
            stdin.fileHandleForWriting.closeFile()
        } catch {
            return BasicCleaner.cleaned(raw)
        }

        var output = Data()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output = stdout.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            done.signal()
        }
        guard done.wait(timeout: .now() + 2) == .success else {
            p.terminate()
            return BasicCleaner.cleaned(raw)
        }
        guard p.terminationStatus == 0 else { return BasicCleaner.cleaned(raw) }

        let cleaned = String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? BasicCleaner.cleaned(raw) : cleaned
    }
}

enum Cleaners {
    /// Helper installed -> canonical TS cleaner, else the Swift port.
    static func best() -> Cleaner {
        BunCleaner.isAvailable() ? BunCleaner() : BasicSwiftCleaner()
    }
}
