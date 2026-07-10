import SwiftUI
import Shared

struct SetupView: View {
    @ObservedObject var setup: EngineSetup
    var onDone: () -> Void = {}
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            macCard
            installTargetRow
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Engine.allCases) { EngineCard(engine: $0, setup: setup) }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.black.color)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Better engines")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Theme.textHi.color)
            Text("All on-device — nothing leaves your Mac. Each one is optional; install only what you want.")
                .font(.system(size: 13))
                .foregroundColor(Theme.mist.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    /// A quick local scan of this Mac — so you can see what you're working with and why an engine may
    /// be unavailable. Nothing leaves the machine.
    private var macCard: some View {
        let m = setup.mac
        return VStack(alignment: .leading, spacing: 8) {
            Text("YOUR MAC").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundColor(Theme.mist.color)
            HStack(spacing: 18) {
                spec("cpu", m.chip)
                spec("memorychip", "\(m.ramGB) GB")
                spec("internaldrive", "\(m.freeDiskGB) GB free")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
        .padding(.horizontal, 20)
    }
    private func spec(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.electric.color)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.textHi.color).lineLimit(1)
        }
    }

    /// Where new downloads land. Anything already on your Mac is reused automatically; this only chooses
    /// where fresh weights are written — the shared memex store (reusable by Breve/Rotli) or warble-only.
    private var installTargetRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.mist.color)
            Text("New downloads").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.mist.color)
            Picker("", selection: $setup.target) {
                Text("Shared store").tag(AIStore.Target.shared)
                Text("warble only").tag(AIStore.Target.app)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Spacer(minLength: 0)
            Text(setup.target == .shared ? "~/.memex/ai — reusable by your memex apps" : "~/.warble — removed with warble")
                .font(.system(size: 11)).foregroundColor(Theme.mist.color).lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.line.color)
            DisclosureGroup(isExpanded: $showDetails) {
                Text("""
                Models live OUTSIDE the app, so deleting warble never deletes them — that's why a fresh \
                download can already show “Installed” (it's reusing what's on your Mac, not re-downloading).
                • Shared store (\u{007E}/.memex/ai) — the big model weights, reusable by your other memex \
                apps (Breve, Rotli).
                • warble only (\u{007E}/.warble) — the small warm-server runtimes; and the models too, if you pick \
                “warble only” above.
                Permissions are requested only the first time you use a feature: Microphone (dictation), \
                Accessibility (typing the result), Speech Recognition (Apple fallback). Everything installs \
                in your home folder — never system-wide, no admin. Every engine runs locally and binds \
                127.0.0.1 only.
                """)
                .font(.system(size: 12))
                .foregroundColor(Theme.mist.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            } label: {
                Label("Permissions & what installs where", systemImage: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.mist.color)
            }
            .tint(Theme.mist.color)
            .padding(.horizontal, 20)
            HStack(spacing: 10) {
                Text("warble lives in your menu bar — reopen this anytime from there.")
                    .font(.system(size: 11)).foregroundColor(Theme.mist.color)
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(FilledButton())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

private struct EngineCard: View {
    let engine: Engine
    @ObservedObject var setup: EngineSetup
    private var state: InstallState { setup.state[engine] ?? .notInstalled }
    private var support: (ok: Bool, reason: String?) { setup.supports(engine) }
    private var disabled: Bool { !support.ok }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.electric.color.opacity(0.14)).frame(width: 44, height: 44)
                Image(systemName: engine.symbol).font(.system(size: 19, weight: .medium)).foregroundColor(Theme.electric.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(engine.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi.color)
                    Text(engine.sizeText).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.mist.color)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.line.color.opacity(0.5)))
                }
                Text(engine.subtitle).font(.system(size: 12)).foregroundColor(Theme.mist.color)
                if let reason = support.reason {
                    // Warn amber is the declared one-accent exception — always paired with a glyph
                    // so color is never the only signal.
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundColor(.orange)
                        Text(reason).font(.system(size: 11, weight: .medium)).foregroundColor(.orange)
                    }
                    .padding(.top, 1)
                }
                if case .installed = state, let src = setup.source(of: engine) {
                    HStack(spacing: 5) {
                        Image(systemName: "shippingbox.fill").font(.system(size: 10)).foregroundColor(Theme.mist.color)
                        Text(src).font(.system(size: 11)).foregroundColor(Theme.mist.color)
                    }
                    .padding(.top, 2)
                }
                progressRow
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
        .opacity(disabled ? 0.5 : 1)
    }

    @ViewBuilder private var progressRow: some View {
        if case let .installing(fraction, status) = state {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction.map { min(max($0, 0), 1) }, total: 1)
                    .progressViewStyle(.linear)
                    .tint(Theme.electric.color)
                    .frame(maxWidth: 320)
                Text(fraction.map { "\(status)… \(Int($0 * 100))%" } ?? "\(status)…")
                    .font(.system(size: 11)).foregroundColor(Theme.mist.color)
            }
            .padding(.top, 5)
        } else if case let .failed(msg) = state {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundColor(.orange)
                Text(msg).font(.system(size: 11)).foregroundColor(.orange)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
        }
    }

    @ViewBuilder private var trailing: some View {
        if !support.ok {
            Text("Unavailable").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.mist.color)
        } else {
            switch state {
            case .installed:
                // Success is a glyph, not a color (one accent only): electric check + plain label.
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(Theme.electric.color)
                    Text("Installed").font(.system(size: 13, weight: .medium)).foregroundColor(Theme.textHi.color)
                }
            case .installing:
                ProgressView().controlSize(.small).tint(Theme.electric.color)
            case .failed:
                Button("Retry") { setup.install(engine) }.buttonStyle(FilledButton())
            case .notInstalled:
                Button("Install") { setup.install(engine) }.buttonStyle(FilledButton())
            }
        }
    }
}

/// The filled primary act (Install, Retry, Done, "Set up better engines"): white on electric-deep —
/// 5.26:1, passes AA — lifting to electric on hover, dimming while pressed. Custom button styles
/// suppress the system focus ring, so the 2px electric-bright ring (the crest's one in-app role)
/// is drawn here. Shared with WelcomeWindow so the two setup surfaces stay one button.
struct FilledButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    // Not named `Body`: that would shadow ButtonStyle's associated type and break conformance.
    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill((hovered ? Theme.electric.color : Theme.electricDeep.color)
                        .opacity(configuration.isPressed ? 0.7 : 1)))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Theme.electricBright.color, lineWidth: 2)
                    .padding(-4)
                    .opacity(focused ? 1 : 0))
                .onHover { hovered = $0 }
        }
    }
}
