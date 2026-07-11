import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import Dictate
import Shared

extension Notification.Name {
    /// Posted by the app coordinator whenever a read-aloud fires (any trigger) — the welcome
    /// tour's read card listens while it's up to light its Next affordance.
    static let warbleDidRead = Notification.Name("warble.didRead")
}

/// The first-run welcome tour (ROADMAP 0.4): the pre-0.4 static welcome card, evolved into a
/// sequential card flow — welcome → one permission per card (Microphone, Accessibility) → the
/// guaranteed-first-success arc (live mic meter → sandboxed practice dictation → read-aloud
/// demo) → finish in the user's own app. Same window plumbing and scale as before; the brain is
/// the pure OnboardingFlow (Shared), so what the cards may do is unit-tested, and the cards
/// render headlessly via `--render-onboarding` (OnboardingCLI). Shown once on a fresh install;
/// existing installs (didShowWelcome already set) never see it; "menu → Welcome tour…" reopens
/// it anytime.
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()
    private var window: NSWindow?
    private let model = OnboardingModel()

    // The first-launch gate. didShowOnboarding is 0.4's key; didShowWelcome is the pre-0.4 card's
    // key, honored so an EXISTING install never sees the tour uninvited on update (the migration —
    // OnboardingGate, unit-tested). markShown sets both, so a downgrade can't re-show the old card.
    private static let key = "didShowOnboarding"
    private static let legacyKey = "didShowWelcome"
    static var shouldShow: Bool {
        OnboardingGate.shouldShow(didShowOnboarding: UserDefaults.standard.bool(forKey: key),
                                  legacyDidShowWelcome: UserDefaults.standard.bool(forKey: legacyKey))
    }
    static func markShown() {
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: legacyKey)
    }

    func open() {
        if window == nil {
            let host = NSHostingView(rootView: OnboardingFlowView(model: model))
            host.sizingOptions = [] // critical: don't let the hosting view resize the window to its content
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = host
            w.center()
            window = w
            model.onFinished = { [weak self] in self?.window?.close() }
        }
        model.restart()
        Self.markShown()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.startPolling()
    }

    /// Covers every exit — Done, Skip tour, and a plain ⌘W/red-button close mid-flow: the
    /// permission poll, the live mic meter, the practice sandbox, and the read listener all stop.
    func windowWillClose(_ notification: Notification) { model.suspend() }
}

// MARK: - The live model

/// Bridges the pure OnboardingFlow to the cards: polls the permission predicates while the window
/// is open (the card's status flips to a checkmark the moment a grant lands — grant-one-reveal-
/// next), and owns the permission actions (the system prompt where the API allows, and the
/// System Settings deep link otherwise).
final class OnboardingModel: ObservableObject {
    @Published private(set) var flow = OnboardingFlow(steps: []) // built by restart() before the window shows
    @Published private(set) var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var axGranted = AXIsProcessTrusted()
    /// The practice card's landed rehearsal (raw → cleaned) — nil until one lands; completes the step.
    @Published private(set) var practiceResult: (raw: String, cleaned: String)?
    /// A real read-aloud fired while the read card was up — completes the step.
    @Published private(set) var readHappened = false
    /// The meter card's live level source. Cards observe it directly; the render seam injects a
    /// fixture through OnboardingCardState.meterLevels instead.
    let meter = MicMeter()
    var onFinished: () -> Void = {}
    private var poll: Timer?
    private var readObserver: Any?

    private func makeFlow() -> OnboardingFlow {
        OnboardingFlow.standard(
            micGranted: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
            axGranted: { AXIsProcessTrusted() },
            practiceDone: { [weak self] in self?.practiceResult != nil },
            readDone: { [weak self] in self?.readHappened ?? false })
    }

    func restart() {
        practiceResult = nil
        readHappened = false
        flow = makeFlow()
        refresh()
        syncStep()
    }

    func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// The window is closing (any path) — stop everything live: the poll, the mic tap, the
    /// practice sandbox, the read listener. Nothing may keep running behind a closed tour.
    func suspend() {
        poll?.invalidate()
        poll = nil
        meter.stop()
        PracticeSandbox.shared.end()
        if let ob = readObserver { NotificationCenter.default.removeObserver(ob); readObserver = nil }
    }

    /// Re-read the live permission state; on any change, republish (the visible card re-renders),
    /// reconcile step side effects (a mic granted via jump-back starts the meter), and refresh
    /// the re-verify baseline so the next macOS update compares against reality.
    private func refresh() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let ax = AXIsProcessTrusted()
        guard mic != micStatus || ax != axGranted else { return }
        micStatus = mic
        axGranted = ax
        PermissionNotice.refreshBaseline()
        syncStep()
    }

    /// The current card's live side effects, reconciled on every step change and permission flip:
    /// the meter taps the mic ONLY while its card is visible (motion law), dictations are
    /// rehearsals ONLY while the practice card is up, and the read card listens for a real
    /// read-aloud only while it shows.
    private func syncStep() {
        let id = flow.current?.id
        if id == "meter" { meter.start() } else { meter.stop() } // start() no-ops when mic isn't granted
        if id == "practice" {
            PracticeSandbox.shared.begin { [weak self] raw, cleaned in
                self?.practiceResult = (raw, cleaned)
            }
        } else {
            PracticeSandbox.shared.end()
        }
        if id == "read" {
            guard readObserver == nil else { return }
            readObserver = NotificationCenter.default.addObserver(
                forName: .warbleDidRead, object: nil, queue: .main) { [weak self] _ in
                self?.readHappened = true
            }
        } else if let ob = readObserver {
            NotificationCenter.default.removeObserver(ob)
            readObserver = nil
        }
    }

    /// Everything the current card needs to draw, as a value — the render seam builds the same
    /// struct from fixtures, so a card can never look different headless than live.
    func cardState() -> OnboardingCardState? {
        guard let step = flow.current else { return nil }
        return OnboardingCardState(
            stepID: step.id,
            stepIndex: flow.index,
            stepCount: flow.steps.count,
            granted: step.isComplete(),
            micDenied: micStatus == .denied || micStatus == .restricted,
            canAdvance: flow.canAdvance,
            micGranted: micStatus == .authorized,
            axGranted: axGranted,
            meterLevels: nil, // live cards observe the MicMeter; only the render seam injects levels
            practiceRaw: practiceResult?.raw,
            practiceCleaned: practiceResult?.cleaned)
    }

    func actions() -> OnboardingCardActions {
        OnboardingCardActions(
            permission: { [weak self] in self?.permissionAction() },
            next: { [weak self] in self?.advance { $0.advance() } },
            skipStep: { [weak self] in self?.advance { $0.skip() } },
            skipTour: { [weak self] in self?.advance { $0.skipAll() } },
            jumpBack: { [weak self] id in self?.advance { $0.jump(to: id) } },
            openApp: { Self.openApp(bundleId: $0) },
            openSetup: { [weak self] in
                self?.onFinished()
                SetupWindow.shared.open()
            })
    }

    private func advance(_ mutate: (inout OnboardingFlow) -> Void) {
        mutate(&flow)
        syncStep()
        if flow.finished { onFinished() }
    }

    /// The finish card's "your own apps" buttons — only apps present on every Mac (Mail, Notes,
    /// Messages). NSWorkspace resolves the real app; a missing one is a quiet no-op, never a dialog.
    private static func openApp(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The current permission card's one button. Mic: trigger the real system prompt while the
    /// API still allows it (.notDetermined), else deep-link to the exact Settings pane.
    /// Accessibility has no prompt API worth firing blind — always the deep link.
    private func permissionAction() {
        switch flow.current?.id {
        case "mic":
            if micStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                    DispatchQueue.main.async { self?.refresh() }
                }
            } else {
                NSWorkspace.shared.open(PermissionNotice.micSettingsURL)
            }
        case "ax":
            NSWorkspace.shared.open(PermissionNotice.axSettingsURL)
        default:
            break
        }
    }
}

/// One card at a time; `.id` resets per-card transient state on every step change.
struct OnboardingFlowView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        if let state = model.cardState() {
            OnboardingCard(state: state, actions: model.actions(), meter: model.meter)
                .id(state.stepID)
        } else {
            Theme.black.color // finished — the window is closing
        }
    }
}

// MARK: - The cards (pure views over a value — shared verbatim with the render seam)

struct OnboardingCardState {
    var stepID: String
    var stepIndex: Int
    var stepCount: Int
    /// The step's completion (for permission cards: granted). Flips the status row to the
    /// electric checkmark — success is a glyph + text-hi, never a green (DESIGN.md).
    var granted: Bool
    /// Mic only: the prompt was already declined, so the button becomes the Settings deep link.
    var micDenied: Bool
    var canAdvance: Bool
    /// Meter/practice cards lean on the mic, the read card on Accessibility: false shows the
    /// plain "wasn't granted" notice + the one-click jump back — never a dead end.
    var micGranted = true
    var axGranted = true
    /// Render seam only: a representative meter frame (live cards observe the MicMeter instead).
    var meterLevels: [CGFloat]?
    /// The practice card's landed rehearsal — nil until a dictation lands in the sandbox.
    var practiceRaw: String?
    var practiceCleaned: String?
}

struct OnboardingCardActions {
    var permission: () -> Void = {}
    var next: () -> Void = {}
    var skipStep: () -> Void = {}
    var skipTour: () -> Void = {}
    var jumpBack: (String) -> Void = { _ in }
    var openApp: (String) -> Void = { _ in }
    var openSetup: () -> Void = {}
}

struct OnboardingCard: View {
    let state: OnboardingCardState
    var actions = OnboardingCardActions()
    /// The live level source for the meter card; nil in the render seam (state.meterLevels rules).
    var meter: MicMeter?

    var body: some View {
        VStack(spacing: 0) {
            content
            Spacer(minLength: 12)
            dots
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.black.color)
    }

    @ViewBuilder private var content: some View {
        switch state.stepID {
        case "welcome": welcome
        case "mic":
            permission(symbol: "mic.fill", title: "Microphone",
                       why: "to hear you — audio never leaves your Mac",
                       note: "warble records only while you hold Fn, and transcribes on this Mac.",
                       waiting: state.micDenied ? "denied — grant it in System Settings" : "not granted yet",
                       button: state.micDenied ? "Open System Settings…" : "Allow microphone")
        case "ax":
            permission(symbol: "accessibility", title: "Accessibility",
                       why: "to type what you say where your cursor is — and read the text you select",
                       note: "macOS asks you to flip the switch for warble in Privacy & Security.",
                       waiting: "not granted yet",
                       button: "Open System Settings…")
        case "meter": meterCard
        case "practice": practice
        case "read": readDemo
        default: finish
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)
            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .semibold)).foregroundColor(Theme.electric.color)
            Text("Welcome to warble").font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textHi.color).padding(.top, 12)
            Text("The voice layer for your Mac. Two gestures — that's it.")
                .font(.system(size: 13)).foregroundColor(Theme.mist.color).padding(.top, 4)

            VStack(spacing: 12) {
                gesture("mic.fill", "Speak to type", "Hold **Fn**, talk, release. warble types the cleaned text where your cursor is — in any app.")
                gesture("text.viewfinder", "Select to hear", "Select text anywhere and press **⌃V**. warble reads it aloud in a warm voice.")
            }
            .padding(.horizontal, 28).padding(.top, 24)

            Text("A couple of quick permissions make both work. Every step is skippable — warble asks for nothing until you use it.")
                .font(.system(size: 12)).foregroundColor(Theme.mist.color).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30).padding(.top, 22)
        }
    }

    private func permission(symbol: String, title: String, why: String, note: String,
                            waiting: String, button: String) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 88) // deeper offset than the list cards: this content is short — sit it near optical center
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold)).foregroundColor(Theme.electric.color)
            Text(title).font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textHi.color).padding(.top, 12)
            Text(why).font(.system(size: 13)).foregroundColor(Theme.mist.color)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 44).padding(.top, 4)

            // The live status row: polling flips it to the granted checkmark while the card is
            // visible. Success is the electric glyph + text-hi (never a green — DESIGN.md).
            HStack(spacing: 8) {
                Image(systemName: state.granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(state.granted ? Theme.electric.color : Theme.mist.color)
                Text(state.granted ? "Granted" : waiting)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(state.granted ? Theme.textHi.color : Theme.mist.color)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
            .padding(.top, 28)

            if !state.granted {
                Button(button) { actions.permission() }
                    .buttonStyle(FilledButton())
                    .padding(.top, 16)
            }

            Text(note).font(.system(size: 11)).foregroundColor(Theme.mist.color)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 44).padding(.top, 16)
        }
    }

    /// "It hears you" — the live proof before any dictation is asked for: bars move with your
    /// voice (the render seam injects state.meterLevels; live cards observe the MicMeter). Mic
    /// skipped → say so plainly and offer the jump back — never a dead end.
    private var meterCard: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 84)
            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .semibold)).foregroundColor(Theme.electric.color)
            Text("It hears you").font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textHi.color).padding(.top, 12)
            if state.micGranted {
                Text("Say something — the bars move with your voice.")
                    .font(.system(size: 13)).foregroundColor(Theme.mist.color).padding(.top, 4)

                Group {
                    if let injected = state.meterLevels {
                        MeterBars(levels: injected)
                    } else if let meter {
                        LiveMeterBars(meter: meter)
                    }
                }
                .frame(height: 56)
                .padding(.horizontal, 32).padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
                .padding(.horizontal, 44).padding(.top, 28)

                Text("Nothing is recorded or transcribed here — it's just the level.")
                    .font(.system(size: 11)).foregroundColor(Theme.mist.color)
                    .padding(.top, 16)
            } else {
                missingPermission(
                    why: "The microphone wasn't granted, so there's nothing to hear yet.",
                    back: "Back to Microphone", target: "mic",
                    note: "Or keep going — warble asks again the first time you dictate.")
            }
        }
    }

    /// The sandboxed practice dictation: the real gesture, the real pipeline — but the result
    /// lands HERE (PracticeSandbox routes it into the card), never in another app, History, or
    /// stats. When it lands, the raw transcript sits struck-through in mist under the prominent
    /// cleaned result — the cleanup visibly working.
    private var practice: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 56)
            Image(systemName: "mic.fill")
                .font(.system(size: 38, weight: .semibold)).foregroundColor(Theme.electric.color)
            Text("Try a dictation").font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textHi.color).padding(.top, 12)
            if state.micGranted {
                Text(.init("Hold **Fn**, say the line below — mess and all — then release."))
                    .font(.system(size: 13)).foregroundColor(Theme.mist.color).padding(.top, 4)

                // The rehearsal field. Pre-seeded with the deliberately messy prompt; the landed
                // dictation's cleaned text replaces it (text-hi — the prominent result).
                VStack(alignment: .leading, spacing: 8) {
                    if let cleaned = state.practiceCleaned {
                        Text(cleaned)
                            .font(.system(size: 15)).foregroundColor(Theme.textHi.color)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("“Umm, let's meet Friday at 3 — no, actually 4pm”")
                            .font(.system(size: 15)).foregroundColor(Theme.mist.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
                .padding(.horizontal, 44).padding(.top, 20)

                if let raw = state.practiceRaw {
                    // The transformation, shown: what you actually said, quietly struck…
                    Text(raw)
                        .font(.system(size: 12)).foregroundColor(Theme.mist.color)
                        .strikethrough(true, color: Theme.mist.color.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 44).padding(.top, 14)
                    // …and the fact that the cleanup did the work (glyph + text-hi, never a green).
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.electric.color)
                        Text("cleaned up — the fillers and the false start are gone")
                            .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textHi.color)
                    }
                    .padding(.top, 8)
                } else {
                    Text("It lands right here — this is a rehearsal, so it never touches History.")
                        .font(.system(size: 11)).foregroundColor(Theme.mist.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 44).padding(.top, 16)
                }
            } else {
                missingPermission(
                    why: "Dictation needs the microphone, and it wasn't granted yet.",
                    back: "Back to Microphone", target: "mic",
                    note: "Or keep going — warble asks again the first time you dictate.")
            }
        }
    }

    /// The read-aloud demo: the REAL feature over a paragraph in the card — select it, press ⌃V,
    /// and the follow-along panel appears. A read while the card is up lights Next.
    private var readDemo: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 48)
            Image(systemName: "text.viewfinder")
                .font(.system(size: 38, weight: .semibold)).foregroundColor(Theme.electric.color)
            Text("Hear it back").font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textHi.color).padding(.top, 12)
            if state.axGranted {
                Text(.init("Select the paragraph below, then press **⌃V**."))
                    .font(.system(size: 13)).foregroundColor(Theme.mist.color).padding(.top, 4)

                Text("This paragraph never leaves your Mac. warble reads it aloud and follows along word by word — ears catch what eyes skim.")
                    .font(.system(size: 15)).foregroundColor(Theme.textHi.color)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
                    .padding(.horizontal, 44).padding(.top, 20)

                HStack(spacing: 8) {
                    Image(systemName: state.granted ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(state.granted ? Theme.electric.color : Theme.mist.color)
                    Text(state.granted ? "Read aloud — that's the second verb" : "waiting for a read…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(state.granted ? Theme.textHi.color : Theme.mist.color)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
                .padding(.top, 20)
            } else {
                missingPermission(
                    why: "Reading a selection needs Accessibility, and it wasn't granted yet.",
                    back: "Back to Accessibility", target: "ax",
                    note: "Or keep going — warble asks the first time you press ⌃V.")
            }
        }
    }

    /// A skipped permission is never a dead end (and never a warn — it's a choice, not a
    /// failure): say it plainly, offer the one-click jump back, and note the contextual re-ask.
    private func missingPermission(why: String, back: String, target: String, note: String) -> some View {
        VStack(spacing: 0) {
            Text(why)
                .font(.system(size: 13)).foregroundColor(Theme.mist.color)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 44).padding(.top, 4)
            // Neutral, not electric: Next is enabled on these cards, and a surface never shows
            // two lit primaries at once (the electric fill IS the "what's next" signal).
            Button(back) { actions.jumpBack(target) }
                .buttonStyle(NeutralButton())
                .padding(.top, 24)
            Text(note)
                .font(.system(size: 11)).foregroundColor(Theme.mist.color)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 44).padding(.top, 16)
        }
    }

    /// The real goal, inside the first minute: a dictation in the user's OWN app. Only apps every
    /// Mac has; Done ends the tour for good (menu → Welcome tour… brings it back).
    private var finish: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 48)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .semibold)).foregroundColor(Theme.electric.color)
            Text("Now do it in your own app").font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textHi.color).padding(.top, 12)
            Text(.init("Hold **Fn** and talk wherever the cursor is."))
                .font(.system(size: 13)).foregroundColor(Theme.mist.color).padding(.top, 4)

            HStack(spacing: 12) {
                appButton("Mail", symbol: "envelope", bundleId: "com.apple.mail")
                appButton("Notes", symbol: "note.text", bundleId: "com.apple.Notes")
                appButton("Messages", symbol: "message", bundleId: "com.apple.MobileSMS")
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                gesture("mic.fill", "Speak to type", "Hold **Fn**, talk, release.")
                gesture("text.viewfinder", "Select to hear", "Select text, press **⌃V**.")
            }
            .padding(.horizontal, 28).padding(.top, 24)

            Text("warble lives in your menu bar — this tour is there anytime, under Welcome tour…")
                .font(.system(size: 11)).foregroundColor(Theme.mist.color).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30).padding(.top, 16)
        }
    }

    /// One "open your app" affordance — neutral (ink fill, hairline): the card's single electric
    /// act stays the Done button (one lit primary per surface).
    private func appButton(_ name: String, symbol: String, bundleId: String) -> some View {
        Button { actions.openApp(bundleId) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium)).foregroundColor(Theme.electric.color)
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textHi.color)
            }
            .frame(width: 84, height: 56)
        }
        .buttonStyle(NeutralTileButton())
    }

    private func gesture(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundColor(Theme.electric.color)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.textHi.color)
                Text(.init(body)).font(.system(size: 12)).foregroundColor(Theme.mist.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
    }

    /// Where you are in the flow — the current dot is the only electric one.
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<state.stepCount, id: \.self) { i in
                Circle().fill(i == state.stepIndex ? Theme.electric.color : Theme.line.color)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, 16)
    }

    /// Every card: whole-flow skip on the left (one click, always — product.md §4.5), the step's
    /// own skip + Next on the right. Next is the grant-one-reveal-next affordance: neutral while
    /// the permission is pending, electric once granted or skipped (FilledButton's disabled look).
    @ViewBuilder private var footer: some View {
        HStack(spacing: 12) {
            if state.stepID == "finish" {
                Button("Set up better engines…") { actions.openSetup() }.buttonStyle(GhostButton())
            } else {
                Button("Skip tour") { actions.skipTour() }.buttonStyle(GhostButton())
            }
            Spacer()
            switch state.stepID {
            case "welcome":
                Button("Get started") { actions.next() }.buttonStyle(FilledButton())
                    .keyboardShortcut(.defaultAction)
            case "finish":
                Button("Done") { actions.next() }.buttonStyle(FilledButton())
                    .keyboardShortcut(.defaultAction)
            default:
                if !state.granted {
                    Button("Skip for now") { actions.skipStep() }.buttonStyle(GhostButton())
                }
                Button("Next") { actions.next() }.buttonStyle(FilledButton())
                    .disabled(!state.canAdvance)
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 24)
    }
}

/// The meter card's live bars: a thin observer so only THIS subtree re-renders at the meter's
/// ~30fps — the rest of the card stays put. Draws the same MeterBars the render seam draws.
private struct LiveMeterBars: View {
    @ObservedObject var meter: MicMeter
    var body: some View { MeterBars(levels: meter.levels) }
}

/// The neutral text button (the meter/practice/read cards' jump back): line fill, text-hi label —
/// the secondary-act idiom of the overlays' neutral circles, as a text button. Same focus ring.
struct NeutralButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    // Not named `Body`: that would shadow ButtonStyle's associated type and break conformance.
    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textHi.color)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.line.color)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(hovered ? 0.08 : 0)))
                    .opacity(configuration.isPressed ? 0.7 : 1))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Theme.electricBright.color, lineWidth: 2)
                    .padding(-4)
                    .opacity(focused ? 1 : 0))
                .onHover { hovered = $0 }
        }
    }
}

/// The finish card's app tiles: a neutral act (ink fill, hairline, text-hi label) with the same
/// hover/pressed/focus story as every other control — the one lit primary stays Done.
struct NeutralTileButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    // Not named `Body`: that would shadow ButtonStyle's associated type and break conformance.
    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.ink.color)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(hovered ? 0.04 : 0))) // hover: the sidebar-row wash
                    .opacity(configuration.isPressed ? 0.7 : 1))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.electricBright.color, lineWidth: 2)
                    .padding(-3)
                    .opacity(focused ? 1 : 0))
                .onHover { hovered = $0 }
        }
    }
}

/// The quiet decline: mist label, no fill — hover brightens it to text-hi, and focus draws the
/// same crest ring as the filled button (a color shift alone is not focus).
struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    // Not named `Body`: that would shadow ButtonStyle's associated type and break conformance.
    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(hovered ? Theme.textHi.color : Theme.mist.color)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Theme.electricBright.color, lineWidth: 2)
                    .padding(-2)
                    .opacity(focused ? 1 : 0))
                .onHover { hovered = $0 }
        }
    }
}
