import AppKit
import SwiftUI
import Shared

/// Headless seams for engine Setup (ROADMAP 0.4 "engine setup friction"), asserted by
/// scripts/regression.sh:
///
///   --engine-sizes                       the sizes-up-front table, one parseable line per
///                                        engine: download, disk footprint, and where the
///                                        weights/runtime land (the shared-store default).
///   --fetch-resume <url> <dest>          (DEBUG) run one ResumableFetch and narrate what it
///                                        did — "resumed from N bytes", "restarted — server
///                                        ignored the range", "already complete" — so resume
///                                        behavior is provable against a loopback fixture
///                                        server with no external network.
///   --render-setup <state> <out.png>     (DEBUG) render the Setup window's content offscreen
///                                        at 2x with a fixture state: fresh | installing |
///                                        installed | failed. No window, no permissions, no
///                                        install machinery.
enum SetupCLI {
    /// Returns true if it handled the args (the caller should then exit).
    static func handle(_ args: [String]) -> Bool {
        if args.contains("--engine-sizes") {
            for e in Engine.allCases {
                let d = e.destination(for: .shared)
                let download = e.downloadSize + (e.lazyDownloadNote.map { " + \($0)" } ?? "")
                print("engine \(e.rawValue) | download \(download) | disk \(e.diskSize) | weights \(d.weights) | runtime \(d.runtime)")
            }
            return true
        }
        #if DEBUG
        if let i = args.firstIndex(of: "--fetch-resume") {
            guard i + 2 < args.count, let url = URL(string: args[i + 1]) else {
                FileHandle.standardError.write(Data("usage: --fetch-resume <url> <dest>\n".utf8))
                exit(2)
            }
            fetchResume(url, to: URL(fileURLWithPath: args[i + 2]))
            return true
        }
        if let i = args.firstIndex(of: "--render-setup") {
            guard i + 2 < args.count else {
                FileHandle.standardError.write(Data("usage: --render-setup <state> <out.png>\n".utf8))
                exit(2)
            }
            MainActor.assumeIsolated { render(state: args[i + 1], to: URL(fileURLWithPath: args[i + 2])) }
            return true
        }
        #else
        for flag in ["--fetch-resume", "--render-setup"] where args.contains(flag) {
            // Never fall through into launching the app because a QA flag hit a release build.
            FileHandle.standardError.write(Data("\(flag) exists in DEBUG builds only\n".utf8))
            exit(2)
        }
        #endif
        return false
    }

    #if DEBUG
    /// One resumable fetch, narrated. The output lines are the check's assertions — keep them
    /// stable (regression greps them verbatim).
    private static func fetchResume(_ url: URL, to dest: URL) {
        let fetch = ResumableFetch()
        do {
            let outcome = try fetch.run(url, to: dest) { _, _ in }
            switch outcome {
            case .alreadyComplete(let n):
                print("already complete (\(n) bytes) — nothing fetched")
            case .fetched(let n):
                if fetch.partialWasComplete {
                    print("partial already held every byte — verified, not refetched")
                } else if fetch.resumeHonored {
                    print("resumed from \(fetch.startedWithPartial) bytes")
                } else if fetch.startedWithPartial > 0 {
                    print("restarted — server ignored the range")
                }
                print("fetched \(n) bytes → \(dest.path)")
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// Render the Setup content view to a PNG at 2x — the same ImageRenderer seam as
    /// --render-onboarding (no window, nothing flashes on screen). Install states are fixtures
    /// injected through EngineSetup's preview init; the Mac card shows this machine's real scan
    /// (it's a live fact, not a state).
    @MainActor private static func render(state: String, to out: URL) {
        let fixtures: [String: [Engine: InstallState]] = [
            // Sizes + destinations visible on every card, before any consent.
            "fresh": [.dictation: .notInstalled, .voices: .notInstalled, .cleanup: .notInstalled],
            // Honest progress, both kinds: a real byte % and a named indeterminate phase —
            // plus the "keep dictating" line that appears while anything installs.
            "installing": [.dictation: .installing(fraction: 0.42, status: "Downloading model"),
                           .voices: .installing(fraction: nil, status: "Unpacking…"),
                           .cleanup: .notInstalled],
            "installed": [.dictation: .installed, .voices: .installed, .cleanup: .installed],
            // Failure is warn + glyph + the script's own last line (never a bare exit code).
            "failed": [.dictation: .notInstalled, .voices: .notInstalled,
                       .cleanup: .failed("python3 not found — install the Xcode Command Line Tools first")],
        ]
        guard let preview = fixtures[state] else {
            FileHandle.standardError.write(
                Data("unknown setup state \"\(state)\" — states: \(fixtures.keys.sorted().joined(separator: " "))\n".utf8))
            exit(2)
        }
        // The window's exact content WIDTH; height is left ideal — the live window scrolls this
        // content, the seam renders all of it (fixture text lengths vary by state and Mac).
        let renderer = ImageRenderer(content: SetupView(setup: EngineSetup(preview: preview), renderSeam: true)
            .frame(width: 560)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("couldn't rasterize the setup view\n".utf8))
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: 560, height: CGFloat(cg.height) / 2)
        guard let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: out)) != nil else {
            FileHandle.standardError.write(Data("couldn't write \(out.path)\n".utf8))
            exit(1)
        }
        print("rendered \(state) → \(out.path)")
    }
    #endif
}
