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
///                                             come from --onboarding-state; a "+variant" suffix
///                                             injects a preview state (mic+granted, ax+granted,
///                                             meter+nomic, practice+done, practice+nomic,
///                                             read+done, read+noax) — see render() below.
enum OnboardingCLI {
    /// Returns true if it handled the args (the caller should then exit).
    static func handle(_ args: [String]) -> Bool {
        if args.contains("--onboarding-state") {
            // The REAL machine over the REAL (read-only, never-prompting) predicates — so the
            // printed steps are exactly what a first launch would walk through on this machine.
            // practice/read complete only when their feature fires live, so headless they are
            // constant-incomplete — exactly a fresh launch's state.
            let flow = OnboardingFlow.standard(
                micGranted: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
                axGranted: { AXIsProcessTrusted() },
                practiceDone: { false },
                readDone: { false })
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
    ///
    /// Preview-state injection: no mic, pipeline, or reader exists headlessly, so a variant
    /// suffix picks the representative state the live model would publish at that moment —
    ///   mic+granted / ax+granted   the permission card's granted look
    ///   meter+nomic                the meter card when the mic was skipped (notice + jump back)
    ///   practice+done              a landed rehearsal: raw struck, cleaned prominent
    ///   practice+nomic             the practice card when the mic was skipped
    ///   read+done                  a read-aloud happened — Next is lit
    ///   read+noax                  the read card when Accessibility was skipped
    /// The bare "meter" renders with a representative mid-speech bar frame injected.
    @MainActor private static func render(step: String, to out: URL) {
        let parts = step.split(separator: "+", maxSplits: 1)
        let id = String(parts[0])
        let variant = parts.count > 1 ? String(parts[1]) : ""
        let ids = ["welcome", "mic", "ax", "meter", "practice", "read", "finish"]
        let variants: [String: [String]] = [
            "mic": ["granted"], "ax": ["granted"], "meter": ["nomic"],
            "practice": ["done", "nomic"], "read": ["done", "noax"],
        ]
        guard let idx = ids.firstIndex(of: id), variant.isEmpty || variants[id]?.contains(variant) == true else {
            let menu = ids.map { id in ([id] + (variants[id] ?? []).map { "\(id)+\($0)" }).joined(separator: " ") }
            FileHandle.standardError.write(Data("unknown onboarding step \"\(step)\" — steps: \(menu.joined(separator: " "))\n".utf8))
            exit(2)
        }
        let constantComplete = ["welcome", "meter", "finish"].contains(id)
        let done = constantComplete || variant == "granted" || variant == "done"
        var state = OnboardingCardState(
            stepID: id,
            stepIndex: idx,
            stepCount: ids.count,
            granted: done,
            micDenied: false,
            canAdvance: done)
        switch variant {
        case "nomic": state.micGranted = false
        case "noax": state.axGranted = false
        case "done" where id == "practice":
            state.practiceRaw = "Umm, let's meet Friday at 3 — no, actually 4pm"
            state.practiceCleaned = "Let's meet Friday at 4pm."
        default: break
        }
        if id == "meter", state.micGranted {
            // A representative mid-speech frame: the meter's own ripple shape at a strong level.
            state.meterLevels = (0..<MicMeter.bars).map { (i: Int) -> CGFloat in
                let ripple: CGFloat = 0.5 + 0.5 * sin(CGFloat(i) * 1.15)
                return max(0.05, 0.85 * (0.40 + 0.60 * ripple))
            }
        }

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
