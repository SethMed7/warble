import SwiftUI

/// voz dark + single-electric-blue palette (mirrors the Insights window's VozTheme, which is internal
/// to the Dictate module — kept in sync by hand; one accent only).
private enum T {
    static let black = Color(red: 0x07 / 255.0, green: 0x08 / 255.0, blue: 0x0C / 255.0)
    static let ink = Color(red: 0x16 / 255.0, green: 0x15 / 255.0, blue: 0x20 / 255.0)
    static let line = Color(red: 0x2A / 255.0, green: 0x28 / 255.0, blue: 0x33 / 255.0)
    static let electric = Color(red: 0x2E / 255.0, green: 0x74 / 255.0, blue: 0xFF / 255.0)
    static let mist = Color(red: 0x8B / 255.0, green: 0x87 / 255.0, blue: 0x94 / 255.0)
    static let textHi = Color(red: 0.93, green: 0.94, blue: 0.96)
    static let good = Color(red: 0x35 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0)
}

struct SetupView: View {
    @ObservedObject var setup: EngineSetup
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            macCard
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Engine.allCases) { EngineCard(engine: $0, setup: setup) }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.black)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Better engines")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(T.textHi)
            Text("All on-device — nothing leaves your Mac. Each one is optional; install only what you want.")
                .font(.system(size: 13))
                .foregroundColor(T.mist)
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
            Text("YOUR MAC").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundColor(T.mist)
            HStack(spacing: 18) {
                spec("cpu", m.chip)
                spec("memorychip", "\(m.ramGB) GB")
                spec("internaldrive", "\(m.freeDiskGB) GB free")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.ink))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line, lineWidth: 1))
        .padding(.horizontal, 20)
    }
    private func spec(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundColor(T.electric)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(T.textHi).lineLimit(1)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(T.line)
            DisclosureGroup(isExpanded: $showDetails) {
                Text("""
                Permissions are requested only the first time you use a feature: Microphone (dictation), \
                Accessibility (typing the result), Speech Recognition (Apple fallback). Everything installs \
                in your home folder — \u{007E}/.voz and \u{007E}/.cache — never system-wide, no admin. \
                Every engine runs locally and binds 127.0.0.1 only.
                """)
                .font(.system(size: 12))
                .foregroundColor(T.mist)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            } label: {
                Label("Permissions & what installs where", systemImage: "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(T.mist)
            }
            .tint(T.mist)
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
                RoundedRectangle(cornerRadius: 10).fill(T.electric.opacity(0.14)).frame(width: 44, height: 44)
                Image(systemName: engine.symbol).font(.system(size: 19, weight: .medium)).foregroundColor(T.electric)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(engine.title).font(.system(size: 15, weight: .semibold)).foregroundColor(T.textHi)
                    Text(engine.sizeText).font(.system(size: 11, weight: .medium)).foregroundColor(T.mist)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(T.line.opacity(0.5)))
                }
                Text(engine.subtitle).font(.system(size: 12)).foregroundColor(T.mist)
                if let reason = support.reason {
                    Text(reason).font(.system(size: 11, weight: .medium)).foregroundColor(.orange).padding(.top, 1)
                }
                progressRow
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(T.ink))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line, lineWidth: 1))
        .opacity(disabled ? 0.5 : 1)
    }

    @ViewBuilder private var progressRow: some View {
        if case let .installing(fraction, status) = state {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction.map { min(max($0, 0), 1) }, total: 1)
                    .progressViewStyle(.linear)
                    .tint(T.electric)
                    .frame(maxWidth: 320)
                Text(fraction.map { "\(status)… \(Int($0 * 100))%" } ?? "\(status)…")
                    .font(.system(size: 11)).foregroundColor(T.mist)
            }
            .padding(.top, 5)
        } else if case let .failed(msg) = state {
            Text(msg).font(.system(size: 11)).foregroundColor(.orange).padding(.top, 3)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var trailing: some View {
        if !support.ok {
            Text("Unavailable").font(.system(size: 12, weight: .medium)).foregroundColor(T.mist)
        } else {
            switch state {
            case .installed:
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(T.good).labelStyle(.titleAndIcon)
            case .installing:
                ProgressView().controlSize(.small).tint(T.electric)
            case .failed:
                Button("Retry") { setup.install(engine) }.buttonStyle(InstallButton())
            case .notInstalled:
                Button("Install") { setup.install(engine) }.buttonStyle(InstallButton())
            }
        }
    }
}

private struct InstallButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(T.electric.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}
