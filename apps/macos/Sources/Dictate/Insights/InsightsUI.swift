import SwiftUI
import AppKit
import Shared

/// The dashboard shell: a Flow-style dark sidebar (Home / Insights / Dictionary / History /
/// Data & Privacy) over a detail pane. Pure content — the window chrome (toolbar, section title,
/// contextual search/filter/export) lives in InsightsWindow.
enum InsightsSection: String, CaseIterable, Identifiable, Hashable {
    case home = "Home", insights = "Insights", dictionary = "Dictionary", history = "History", data = "Data & Privacy"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .insights: return "chart.bar"
        case .dictionary: return "character.book.closed"
        case .history: return "clock.arrow.circlepath"
        case .data: return "lock.shield"
        }
    }
}

/// Lets the menu deep-link to a section (e.g. "Dictionary…" opens the window on Dictionary).
final class InsightsNav: ObservableObject {
    @Published var section: InsightsSection = .home
    @Published var showTutorial = false
    /// History's live filters — owned here so the window's toolbar (AppKit) and HistoryView
    /// (SwiftUI) read and write the same state.
    @Published var historySearch = ""
    @Published var historyAppFilter: String? = nil
}

/// Captures each sidebar row's on-screen frame (in the shared coordinate space) so the tutorial can
/// point a callout at the real row instead of floating a card in the middle of the window.
struct RowFrameKey: PreferenceKey {
    static var defaultValue: [InsightsSection: CGRect] = [:]
    static func reduce(value: inout [InsightsSection: CGRect], nextValue: () -> [InsightsSection: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct InsightsRootView: View {
    @ObservedObject var store: InsightStore
    @ObservedObject var nav: InsightsNav
    @StateObject private var ai = AIInsightsStore()
    @State private var rowFrames: [InsightsSection: CGRect] = [:]
    @FocusState private var focusedRow: InsightsSection?

    static let space = "insights.coach"

    var body: some View {
        // A FIXED two-pane layout instead of NavigationSplitView: the sidebar is always visible and
        // never collapses, and nothing injects a toolbar sidebar-toggle — that auto toggle, whose
        // position shifted with the (collapsed) state, was the icon that "jumped" around the titlebar,
        // and its collapse is what made the sidebar unusable. Selection is plain `nav.section`.
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 212)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(WarbleTheme.ink)
                // A Divider stops at the safe-area edge; the toolbar strip above would show a gap.
                Rectangle().fill(WarbleTheme.line).frame(width: 1).ignoresSafeArea(edges: .top)
                detail
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                    .background(WarbleTheme.black)
            }

            if nav.showTutorial {
                TutorialOverlay(nav: nav, frames: rowFrames).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
        .preferredColorScheme(.dark)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
    }

    /// The fixed sidebar: brand header + the section rows. The toolbar's safe-area inset already
    /// clears the titlebar; the small top padding is just breathing room.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: WarbleMark.coloredMark(height: 22))
                Text("warble").font(.headline).foregroundStyle(WarbleTheme.textHi)
                Text("Dashboard").font(.headline).foregroundStyle(WarbleTheme.mist)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)

            ForEach(InsightsSection.allCases) { s in sidebarRow(s) }
            Spacer(minLength: 0)
        }
    }

    /// One selectable row. Publishes its frame (RowFrameKey) so the coachmark tour can spotlight it —
    /// the GeometryReader background must stay right here in the chain (after the row's own padding
    /// and background, before the outer horizontal padding) or the coachmarks shift.
    private func sidebarRow(_ s: InsightsSection) -> some View {
        SidebarRow(section: s, selected: nav.section == s, focused: focusedRow == s) { nav.section = s }
            .focused($focusedRow, equals: s)
            .background(GeometryReader { geo in
                Color.clear.preference(key: RowFrameKey.self,
                                       value: [s: geo.frame(in: .named(Self.space))])
            })
            .padding(.horizontal, 8)
    }

    /// The detail pane for the selected section.
    @ViewBuilder private var detail: some View {
        switch nav.section {
        case .home: HomeView(store: store)
        case .insights: InsightsView(store: store, ai: ai)
        case .dictionary: DictionaryView()
        case .history: HistoryView(store: store, nav: nav)
        case .data: DataPrivacyView(store: store)
        }
    }
}

/// A sidebar row as a real Button (Space/Return activate it when focused). Hover is a neutral lift —
/// no second hue, the accent stays on selection — and keyboard focus draws the same 2px
/// electric-bright (crest) ring as FilledButton/GhostButton, because the system ring on `.plain`
/// buttons is unreliable on macOS 13.
private struct SidebarRow: View {
    let section: InsightsSection
    let selected: Bool
    let focused: Bool
    let activate: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 10) {
                Image(systemName: section.icon).frame(width: 20)
                Text(section.rawValue)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? WarbleTheme.textHi : WarbleTheme.mist)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(WarbleTheme.electricBright, lineWidth: 2)
                .padding(-2)
                .opacity(focused ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var fill: Color {
        if selected { return WarbleTheme.electric.opacity(0.18) }
        if hovered { return Color.white.opacity(0.04) }
        return .clear
    }
}

/// A short, skippable coachmark tour: each step spotlights the matching sidebar row and points a callout
/// at it (arrow on the left), advancing row-to-row on Next — so the tour teaches the actual UI instead of
/// floating a card in the middle of a dimmed window. Shown once, right after engine setup finishes.
struct TutorialOverlay: View {
    @ObservedObject var nav: InsightsNav
    let frames: [InsightsSection: CGRect]
    @State private var step = 0

    private struct Step { let title: String; let body: String; let section: InsightsSection; let icon: String }
    private let steps: [Step] = [
        .init(title: "This is your dashboard", body: "Everything warble records and learns lives here — and only here, on your Mac.", section: .home, icon: "square.grid.2x2"),
        .init(title: "History", body: "Every dictation, searchable. Open one to replay the audio, fix the text, or teach warble a word.", section: .history, icon: "clock.arrow.circlepath"),
        .init(title: "Dictionary", body: "Your learned spellings and read-aloud pronunciations — warble gets them right next time.", section: .dictionary, icon: "character.book.closed"),
        .init(title: "Insights", body: "Trends over time: words per day, speaking pace, and where you dictate most.", section: .insights, icon: "chart.bar"),
        .init(title: "Data & Privacy", body: "You're in control — keep history or not, save recordings or not, skip password fields. Nothing ever leaves your Mac.", section: .data, icon: "lock.shield"),
    ]

    private let cardWidth: CGFloat = 300
    private let arrowW: CGFloat = 11
    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                spotlight(in: geo.size, hole: frames[steps[step].section])
                callout(in: geo.size, row: frames[steps[step].section])
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 0.22), value: step)
        }
        // No .ignoresSafeArea() here: the row frames are measured in the root ZStack's named space,
        // which starts BELOW the toolbar's safe-area inset — expanding above it would draw every
        // spotlight and callout ~52pt too high. The toolbar strip stays undimmed, same as the
        // traffic lights (window chrome sits above the contentView; SwiftUI can't dim it anyway).
        .onAppear { nav.section = steps[0].section }
    }

    /// Dim everything except a rounded cutout around the active row, ringed in electric blue.
    private func spotlight(in size: CGSize, hole: CGRect?) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .mask(
                ZStack {
                    Rectangle().fill(Color.white)
                    if let h = hole {
                        RoundedRectangle(cornerRadius: 7).fill(Color.black)
                            .frame(width: h.width, height: h.height)
                            .position(x: h.midX, y: h.midY)
                            .blendMode(.destinationOut)
                    }
                }.compositingGroup()
            )
            .overlay(
                Group {
                    if let h = hole {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(WarbleTheme.electric.opacity(0.85), lineWidth: 1.5)
                            .frame(width: h.width, height: h.height)
                            .position(x: h.midX, y: h.midY)
                    }
                }
            )
            .contentShape(Rectangle()) // swallow clicks on the dimmed area
    }

    /// The callout card + left arrow, anchored just right of the active row (centered if no frame yet).
    private func callout(in size: CGSize, row: CGRect?) -> some View {
        let hasRow = (row?.width ?? 0) > 0
        let r = row ?? .zero
        let centerY = min(max(r.midY, 96), size.height - 96)
        let cx = r.maxX + gap + arrowW / 2 + cardWidth / 2
        return Group {
            if hasRow {
                HStack(spacing: 0) {
                    LeftArrow().fill(WarbleTheme.ink).frame(width: arrowW, height: 18)
                    cardBody
                }
                .position(x: cx, y: centerY)
            } else {
                cardBody.position(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: steps[step].icon).font(.system(size: 16, weight: .medium)).foregroundStyle(WarbleTheme.electric)
                Text(steps[step].title).font(.system(size: 16, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
                Spacer()
                Button("Skip") { finish() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WarbleTheme.mist)
            }
            Text(steps[step].body).font(.system(size: 12.5)).foregroundStyle(WarbleTheme.mist)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle().fill(i == step ? WarbleTheme.electric : WarbleTheme.line).frame(width: 6, height: 6)
                }
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1; nav.section = steps[step].section } }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WarbleTheme.mist)
                }
                Button(step == steps.count - 1 ? "Done" : "Next") { advance() }
                    .buttonStyle(TutorialButton()).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(width: cardWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(WarbleTheme.ink))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WarbleTheme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }

    private func advance() {
        if step < steps.count - 1 { withAnimation { step += 1; nav.section = steps[step].section } } else { finish() }
    }
    private func finish() {
        UserDefaults.standard.set(true, forKey: "didShowTutorial")
        withAnimation { nav.showTutorial = false }
    }
}

/// A small left-pointing triangle for the coachmark callout (its tip sits beside the highlighted row).
private struct LeftArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct TutorialButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(WarbleTheme.electric.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}

/// Home: the locked must-have stat cards + a recent feed.
struct HomeView: View {
    @ObservedObject var store: InsightStore

    private var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Welcome back, \(firstName)",
                           subtitle: "Your dictation at a glance — words, pace, streak, and recent activity.")

                HStack(spacing: 14) {
                    StatCard(value: store.totalWordsCompact, label: "words dictated")
                    StatCard(value: "\(store.avgWPM)", label: "wpm")
                    StatCard(value: "\(store.dayStreak)", label: "day streak")
                    StatCard(value: store.wordsReadCompact, label: "words read")
                }

                if store.events.isEmpty {
                    EmptyHome()
                } else {
                    Text("Recent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WarbleTheme.mist)
                        .textCase(.uppercase)
                    VStack(spacing: 0) {
                        ForEach(store.events.suffix(8).reversed()) { e in
                            RecentRow(event: e)
                            if e.id != store.events.suffix(8).reversed().last?.id {
                                Divider().overlay(WarbleTheme.line)
                            }
                        }
                    }
                    .background(WarbleTheme.ink, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WarbleTheme.line, lineWidth: 1))

                    if !store.perApp.isEmpty {
                        Text("Where you dictate")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WarbleTheme.mist).textCase(.uppercase)
                            .padding(.top, 8)
                        let maxWords = store.perApp.first?.words ?? 1
                        VStack(spacing: 12) {
                            ForEach(store.perApp.prefix(5)) { app in
                                PerAppRow(app: app, maxWords: maxWords)
                            }
                        }
                        .padding(16)
                        .background(WarbleTheme.ink, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WarbleTheme.line, lineWidth: 1))
                    }
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
    }
}

struct PerAppRow: View {
    let app: InsightStore.AppUsage
    let maxWords: Int
    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleId: app.id, size: 18)
            Text(app.name).font(.system(size: 12)).foregroundStyle(WarbleTheme.textHi)
                .frame(width: 120, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WarbleTheme.line)
                    Capsule().fill(WarbleTheme.electric)
                        .frame(width: max(6, geo.size.width * CGFloat(app.words) / CGFloat(max(1, maxWords))))
                }
            }
            .frame(height: 8)
            Text("\(app.words)").font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(WarbleTheme.textHi)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(WarbleTheme.mist)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarbleTheme.ink, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WarbleTheme.line, lineWidth: 1))
    }
}

private struct RecentRow: View {
    let event: DictationEvent
    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Self.time.string(from: event.date))
                .font(.system(size: 12))
                .foregroundStyle(WarbleTheme.mist)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.text.isEmpty ? "\(event.words) words" : event.text)
                    .font(.system(size: 13))
                    .foregroundStyle(WarbleTheme.textHi)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let app = event.appName {
                        Text(app).font(.system(size: 11)).foregroundStyle(WarbleTheme.electricText)
                    }
                    Text("· \(event.words) words · \(event.wpm) wpm")
                        .font(.system(size: 11))
                        .foregroundStyle(WarbleTheme.mist)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct EmptyHome: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic").font(.system(size: 28)).foregroundStyle(WarbleTheme.electric)
            Text("**Hold Fn and speak** — your words, streak, and pace build up here. Select text and press ⌃V to hear it read aloud.")
                .font(.system(size: 13))
                .foregroundStyle(WarbleTheme.mist)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(WarbleTheme.ink, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WarbleTheme.line, lineWidth: 1))
    }
}

/// Every section opens with the same header: the section name and one plain line saying what
/// this page is for — same scale everywhere so switching sections doesn't jump.
struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(WarbleTheme.textHi)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
        }
    }
}

/// A first-run empty state: what this page will show and the one action that starts filling it.
/// No "coming soon" — the feature is here, the data isn't yet.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String // ends with the action, e.g. "Hold Fn and speak."
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(WarbleTheme.electric)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(WarbleTheme.mist)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
