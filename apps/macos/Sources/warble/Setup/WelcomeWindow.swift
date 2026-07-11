import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import Shared

/// The first-run welcome tour (ROADMAP 0.4): the pre-0.4 static welcome card, evolved into a
/// sequential card flow — welcome → one permission per card (Microphone, Accessibility) → done.
/// Same window plumbing and scale as before; the brain is the pure OnboardingFlow (Shared),
/// so what the cards may do is unit-tested, and the cards render headlessly via
/// `--render-onboarding` (OnboardingCLI). Shown once on a fresh install; existing installs
/// (didShowWelcome already set) never see it; "menu → Welcome tour…" reopens it anytime.
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

    /// Covers every exit — Done, Skip tour, and a plain ⌘W/red-button close mid-flow.
    func windowWillClose(_ notification: Notification) { model.stopPolling() }
}

// MARK: - The live model

/// Bridges the pure OnboardingFlow to the cards: polls the permission predicates while the window
/// is open (the card's status flips to a checkmark the moment a grant lands — grant-one-reveal-
/// next), and owns the permission actions (the system prompt where the API allows, and the
/// System Settings deep link otherwise).
final class OnboardingModel: ObservableObject {
    @Published private(set) var flow = OnboardingModel.makeFlow()
    @Published private(set) var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var axGranted = AXIsProcessTrusted()
    var onFinished: () -> Void = {}
    private var poll: Timer?

    private static func makeFlow() -> OnboardingFlow {
        OnboardingFlow.standard(
            micGranted: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
            axGranted: { AXIsProcessTrusted() })
    }

    func restart() {
        flow = Self.makeFlow()
        refresh()
    }

    func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    /// Re-read the live permission state; on any change, republish (the visible card re-renders)
    /// and refresh the re-verify baseline so the next macOS update compares against reality.
    private func refresh() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let ax = AXIsProcessTrusted()
        guard mic != micStatus || ax != axGranted else { return }
        micStatus = mic
        axGranted = ax
        PermissionNotice.refreshBaseline()
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
            canAdvance: flow.canAdvance)
    }

    func actions() -> OnboardingCardActions {
        OnboardingCardActions(
            permission: { [weak self] in self?.permissionAction() },
            next: { [weak self] in self?.advance { $0.advance() } },
            skipStep: { [weak self] in self?.advance { $0.skip() } },
            skipTour: { [weak self] in self?.advance { $0.skipAll() } },
            openSetup: { [weak self] in
                self?.onFinished()
                SetupWindow.shared.open()
            })
    }

    private func advance(_ mutate: (inout OnboardingFlow) -> Void) {
        mutate(&flow)
        if flow.finished { onFinished() }
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
            OnboardingCard(state: state, actions: model.actions())
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
}

struct OnboardingCardActions {
    var permission: () -> Void = {}
    var next: () -> Void = {}
    var skipStep: () -> Void = {}
    var skipTour: () -> Void = {}
    var openSetup: () -> Void = {}
}

struct OnboardingCard: View {
    let state: OnboardingCardState
    var actions = OnboardingCardActions()

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

    private var finish: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 56)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .semibold)).foregroundColor(Theme.electric.color)
            Text("You're set").font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textHi.color).padding(.top, 12)
            Text("Two gestures, anywhere on your Mac.")
                .font(.system(size: 13)).foregroundColor(Theme.mist.color).padding(.top, 4)

            VStack(spacing: 12) {
                gesture("mic.fill", "Speak to type", "Hold **Fn**, talk, release.")
                gesture("text.viewfinder", "Select to hear", "Select text, press **⌃V**.")
            }
            .padding(.horizontal, 28).padding(.top, 24)

            Text("warble lives in your menu bar — this tour is there anytime, under Welcome tour…")
                .font(.system(size: 12)).foregroundColor(Theme.mist.color).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30).padding(.top, 22)
        }
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
