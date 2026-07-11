import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import Shared

/// Headless seams for the onboarding flow (asserted by scripts/regression.sh):
///
///   --onboarding-state                        the machine, one parseable line per step:
///                                             "step <id> complete=yes|no skippable=yes"
///   --render-onboarding <step-id> <out.png>   (DEBUG builds) render one card offscreen at 2x —
///                                             no window shown, no permissions touched. Step ids
///                                             come from --onboarding-state; "<id>+granted" shows
///                                             a permission card's granted look.
enum OnboardingCLI {
    /// Returns true if it handled the args (the caller should then exit).
    static func handle(_ args: [String]) -> Bool {
        if args.contains("--onboarding-state") {
            // The REAL machine over the REAL (read-only, never-prompting) predicates — so the
            // printed steps are exactly what a first launch would walk through on this machine.
            let flow = OnboardingFlow.standard(
                micGranted: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
                axGranted: { AXIsProcessTrusted() })
            for s in flow.steps {
                print("step \(s.id) complete=\(s.isComplete() ? "yes" : "no") skippable=\(s.skippable ? "yes" : "no")")
            }
            return true
        }
        #if DEBUG
        if let i = args.firstIndex(of: "--render-onboarding") {
            guard i + 2 < args.count else {
                // Never fall through into launching the app on a malformed QA invocation.
                FileHandle.standardError.write(Data("usage: --render-onboarding <step-id> <out.png>\n".utf8))
                exit(2)
            }
            // CLI handling runs on the main thread before NSApplication starts; ImageRenderer is
            // MainActor-bound, so state the fact rather than hop.
            let (step, out) = (args[i + 1], URL(fileURLWithPath: args[i + 2]))
            MainActor.assumeIsolated { render(step: step, to: out) }
            return true
        }
        #else
        if args.contains("--render-onboarding") {
            // Never fall through into launching the app because a QA flag hit a release build.
            FileHandle.standardError.write(Data("--render-onboarding exists in DEBUG builds only\n".utf8))
            exit(2)
        }
        #endif
        return false
    }

    #if DEBUG
    /// Render one card to a PNG at 2x, the UI-verification seam for the tour: the exact
    /// OnboardingCard view the window hosts, rasterized offscreen by SwiftUI's ImageRenderer —
    /// no window ever exists, nothing flashes on screen, and no permission/TCC state is read
    /// (the card state is a fixture). (NSHostingView + cacheDisplay was tried first and silently
    /// drops most of the never-shown view tree; ImageRenderer is the supported headless path.)
    @MainActor private static func render(step: String, to out: URL) {
        let parts = step.split(separator: "+", maxSplits: 1)
        let id = String(parts[0])
        let granted = parts.count > 1 && parts[1] == "granted"
        let ids = ["welcome", "mic", "ax", "finish"]
        guard let idx = ids.firstIndex(of: id) else {
            FileHandle.standardError.write(Data("unknown onboarding step \"\(step)\" — steps: \(ids.joined(separator: " ")) (optionally +granted)\n".utf8))
            exit(2)
        }
        let state = OnboardingCardState(
            stepID: id,
            stepIndex: idx,
            stepCount: ids.count,
            granted: granted || id == "welcome" || id == "finish", // non-permission cards are always complete
            micDenied: false,
            canAdvance: granted || id == "welcome" || id == "finish")

        let size = NSSize(width: 460, height: 540) // the welcome window's exact content size
        let renderer = ImageRenderer(content: OnboardingCard(state: state)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2 // 2x pixels over 1x points = @2x
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("couldn't rasterize the card\n".utf8))
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = size
        guard let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: out)) != nil else {
            FileHandle.standardError.write(Data("couldn't write \(out.path)\n".utf8))
            exit(1)
        }
        print("rendered \(step) → \(out.path)")
    }
    #endif
}
