import SwiftUI
import AppKit
import Shared

/// The dashboard shell: a Flow-style dark sidebar (Home / Insights / Dictionary / History /
/// Data & Privacy) over a detail pane. Pure content — the window chrome (toolbar, section title,
/// contextual search/filter/export) lives in InsightsWindow.
enum InsightsSection: String, CaseIterable, Identifiable, Hashable {
    case home = "Home", insights = "Insights", dictionary = "Dictionary", snippets = "Snippets",
         shortcuts = "Shortcuts", history = "History", data = "Data & Privacy"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .insights: return "chart.bar"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.insert"
        case .shortcuts: return "keyboard"
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
                    .frame(width: 200)
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

    /// The build the user is running — same read as `--version`; the fallback matches main.swift.
    private static let version =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.7.0"

    /// The fixed sidebar: brand header, the section rows, and a version footer. The toolbar's
    /// safe-area inset already clears the titlebar; the small top padding is just breathing room.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: WarbleMark.coloredMark(height: 18))
                Text("warble").font(.system(size: 13, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(InsightsSection.allCases) { s in sidebarRow(s) }
            Spacer(minLength: 0)

            Text(Self.version)
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(WarbleTheme.mist)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
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
        case .home: HomeView(store: store, nav: nav)
        case .insights: InsightsView(store: store, ai: ai)
        case .dictionary: DictionaryView()
        case .snippets: SnippetsView()
        case .shortcuts: ShortcutsView()
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
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(section.rawValue)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? WarbleTheme.textHi : WarbleTheme.mist)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(WarbleTheme.electricBright, lineWidth: 2)
                .padding(-2)
                .opacity(focused ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var fill: Color {
        if selected { return WarbleTheme.electric.opacity(0.15) }
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
                        RoundedRectangle(cornerRadius: 6).fill(Color.black)
                            .frame(width: h.width, height: h.height)
                            .position(x: h.midX, y: h.midY)
                            .blendMode(.destinationOut)
                    }
                }.compositingGroup()
            )
            .overlay(
                Group {
                    if let h = hole {
                        RoundedRectangle(cornerRadius: 6)
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

// MARK: - Shared dashboard primitives (content on the window background, no decorative boxes)

/// A 1px `line` hairline — the dashboard's only grouping chrome besides spacing and alignment.
struct Hairline: View {
    var body: some View { Rectangle().fill(WarbleTheme.line).frame(height: 1) }
}

/// An in-content section header: 13pt semibold, optionally with a small trailing accent action
/// ("See all →"). Never a hero headline, never an ALL-CAPS eyebrow.
struct SectionHeader: View {
    let title: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
            Spacer(minLength: 0)
            if let label = actionLabel, let run = action {
                Button(action: run) {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(WarbleTheme.electricText)
                        .underline(hovered)
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 }
            }
        }
    }
}

/// The list rows' fixed time gutter: clock time today, a short day otherwise — both fit ~56pt at 11pt.
enum RowTime {
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd"); return f
    }()
    static func string(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? clock.string(from: date) : day.string(from: date)
    }
}

/// A first-run empty state: one plain line plus a one-line hint that starts filling it.
/// No "coming soon" — the feature is here, the data isn't yet.
struct EmptyState: View {
    let title: String
    let hint: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
            Text(hint).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 40)
    }
}

// MARK: - Home

/// Home: the four locked stats in one hairline-divided row, the retention pass underneath it (a
/// WPM/typist framing, a corrections-cleaned counter, word counts in human units, the streak
/// heatmap, visible learning in the feed, and a share-card export), the recent feed, and the
/// per-app bars — all sitting directly on the window background.
struct HomeView: View {
    @ObservedObject var store: InsightStore
    @ObservedObject var nav: InsightsNav
    /// --render-home only: ImageRenderer can't resolve a SwiftUI ScrollView's content height
    /// without a bounded viewport, so the seam swaps the scroll container for a plain stack sized
    /// to its own ideal height — the content is identical (the DictationDetailView `renderSeam`
    /// idiom already proven by --render-history).
    var renderSeam = false

    var body: some View {
        Group {
            if renderSeam { content } else { ScrollView { content } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Save a stats card" (ROADMAP 0.6): one button, only once there's something real to
            // share — an empty card would just be a branding graphic, not a stat.
            if !store.dictations.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    ShareCardButton { ShareCard.save(store: store) }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }

            StatRow(stats: [
                (store.totalWordsCompact, "words dictated"),
                ("\(store.avgWPM)", "wpm"),
                ("\(store.dayStreak)", "day streak"),
                (store.wordsReadCompact, "words read"),
            ])
            .padding(.horizontal, 28)

            // WPM framed against published TYPING averages, the corrections-cleaned counter, and
            // word counts translated into everyday things (ROADMAP 0.6 — never a fabricated
            // dictation-population percentile; product.md §4.9). All three are nil (so nothing
            // renders) until there's something real to report.
            VStack(alignment: .leading, spacing: 3) {
                if let line = TypingBaseline.headline(wpm: store.avgWPM) {
                    Text(line).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                }
                if let line = CorrectionsCleaned.headline(store.correctionsCleanedTotal) {
                    Text(line).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                }
                if let line = HumanUnits.headline(totalWords: store.totalWords,
                                                  activeDays: store.daysSinceFirstDictation) {
                    Text(line).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)

            if store.events.isEmpty {
                EmptyState(title: "Nothing here yet",
                           hint: "Hold Fn and speak — your words, streak, and pace build up here.")
                    .padding(.top, 24)
            } else {
                // The streak heatmap (ROADMAP 0.6): a GitHub-style day grid integrating the same
                // day-streak stat above with ~12 weeks of activity, tinted by the one accent only.
                if !store.dictations.isEmpty {
                    SectionHeader(title: "Your streak")
                        .padding(.horizontal, 28)
                        .padding(.top, 32)
                        .padding(.bottom, 12)
                    HStack(alignment: .center, spacing: 20) {
                        StreakHeatmap(cells: Heatmap.cells(wordsByDay: store.wordsByDayAll))
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(store.dayStreak)")
                                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(WarbleTheme.textHi)
                            Text("day streak")
                                .font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                        }
                    }
                    .padding(.horizontal, 28)
                }

                SectionHeader(title: "Recent", actionLabel: "See all →") { nav.section = .history }
                    .padding(.horizontal, 28)
                    .padding(.top, 32)
                    .padding(.bottom, 4)
                recentRows
                    .padding(.horizontal, 20)

                if !store.perApp.isEmpty {
                    SectionHeader(title: "Where you dictate")
                        .padding(.horizontal, 28)
                        .padding(.top, 32)
                        .padding(.bottom, 12)
                    let maxWords = store.perApp.first?.words ?? 1
                    VStack(spacing: 10) {
                        ForEach(store.perApp.prefix(5)) { app in
                            PerAppRow(app: app, maxWords: maxWords)
                        }
                    }
                    .padding(.horizontal, 28)
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 28)
    }

    /// The last 8 feed items — dictations, reads, and "warble learned" moments (ROADMAP 0.6 —
    /// visible learning), merged and sorted by time — as full-bleed rows with inset hairlines. A
    /// dictation/read row jumps to History; a learned row doesn't (nothing to replay there).
    private var recentRows: some View {
        let recent = store.recentFeed(limit: 8)
        return VStack(spacing: 0) {
            ForEach(recent) { item in
                FeedRow(item: item) { nav.section = .history }
                if item.id != recent.last?.id {
                    // Inset both ends to the text column so the hairline sits on the 28pt page grid.
                    Hairline().padding(.leading, 76).padding(.trailing, 8)
                }
            }
        }
    }
}

/// The stat row: no boxes — numerals over labels, columns split by 1px vertical hairlines.
private struct StatRow: View {
    let stats: [(value: String, label: String)]
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { i, s in
                if i > 0 { Rectangle().fill(WarbleTheme.line).frame(width: 1, height: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.value)
                        .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(WarbleTheme.textHi)
                    Text(s.label)
                        .font(.system(size: 11))
                        .foregroundStyle(WarbleTheme.mist)
                }
                .padding(.leading, i == 0 ? 0 : 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PerAppRow: View {
    let app: InsightStore.AppUsage
    let maxWords: Int
    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleId: app.id, size: 18)
            Text(app.name).font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
                .frame(width: 120, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WarbleTheme.line)
                    Capsule().fill(WarbleTheme.electric)
                        .frame(width: max(6, geo.size.width * CGFloat(app.words) / CGFloat(max(1, maxWords))))
                }
            }
            .frame(height: 8)
            Text("\(app.words)").font(.system(size: 11)).monospacedDigit().foregroundStyle(WarbleTheme.mist)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

/// One recent-feed row: time gutter, two-line text, app + counts metadata. Hover is a subtle ink
/// fill — the row is a real button that jumps to History.
private struct RecentRow: View {
    let event: DictationEvent
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                Text(RowTime.string(event.date))
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(WarbleTheme.mist)
                    .frame(width: 56, alignment: .trailing)
                    .padding(.top, 2) // optical align with the 13pt first line
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.text.isEmpty ? "\(event.words) words" : event.text)
                        .font(.system(size: 13))
                        .foregroundStyle(WarbleTheme.textHi)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        if let app = event.appName {
                            Text(app).foregroundStyle(WarbleTheme.electricText)
                        }
                        Text(event.kind == "read" ? "· \(event.words) words"
                                                  : "· \(event.words) words · \(event.wpm) wpm")
                            .foregroundStyle(WarbleTheme.mist)
                    }
                    .font(.system(size: 11))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovered ? WarbleTheme.ink : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
    }
}

/// One row in Home's recent feed: a real dictation/read (RecentRow, unchanged) or a "warble
/// learned" moment (ROADMAP 0.6 — visible learning).
private struct FeedRow: View {
    let item: InsightStore.FeedItem
    let open: () -> Void
    var body: some View {
        switch item {
        case .dictation(let e): RecentRow(event: e, open: open)
        case .learned(let e): LearnedRow(event: e)
        }
    }
}

/// "learned: Myela — from your correction" (ROADMAP 0.6 — visible learning): reuses RecentRow's
/// anatomy (time gutter, one text line, a meta line, a trailing glyph) but isn't a button — there's
/// nothing to open, it's a dictionary moment, not a dictation. The dictionary glyph in
/// electric-text keeps the One-Accent Rule (small accent text/glyph only, never solid electric).
private struct LearnedRow: View {
    let event: InsightStore.LearnedEvent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(RowTime.string(Date(timeIntervalSince1970: event.ts)))
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(WarbleTheme.mist)
                .frame(width: 56, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("learned: \(event.word)")
                    .font(.system(size: 13))
                    .foregroundStyle(WarbleTheme.textHi)
                Text("from your correction")
                    .font(.system(size: 11))
                    .foregroundStyle(WarbleTheme.mist)
            }
            Spacer(minLength: 0)
            Image(systemName: "character.book.closed")
                .font(.system(size: 12))
                .foregroundStyle(WarbleTheme.electricText)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

/// The streak heatmap (ROADMAP 0.6 — GitHub-style day grid, last ~12 weeks): 12 columns of 7
/// consecutive days, oldest to newest, left to right — each cell tinted by the SAME accent at
/// increasing opacity, never a second hue (DESIGN.md's One-Accent Rule). An empty (level 0) day
/// sits on `line`, not a darker "zero" tint, so the grid reads as a calendar, not a bar chart.
struct StreakHeatmap: View {
    let cells: [Heatmap.Cell]
    private let cellSize: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        let weeks = stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<Swift.min($0 + 7, cells.count)])
        }
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: gap) {
                    ForEach(week) { cell in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fill(for: cell.level))
                            .frame(width: cellSize, height: cellSize)
                            .help("\(cell.words) word\(cell.words == 1 ? "" : "s") · \(cell.id)")
                    }
                }
            }
        }
    }

    private func fill(for level: Int) -> Color {
        switch level {
        case 0:  return WarbleTheme.line
        case 1:  return WarbleTheme.electric.opacity(0.25)
        case 2:  return WarbleTheme.electric.opacity(0.45)
        case 3:  return WarbleTheme.electric.opacity(0.7)
        default: return WarbleTheme.electric
        }
    }
}

/// "Save a stats card" (ROADMAP 0.6): the button-primary token pair (DESIGN.md components —
/// electric-deep fill, electric on hover, 70%-opacity pressed) — Home's one filled-text button.
/// A real `ButtonStyle` (the same idiom as `TutorialButton` above and WelcomeWindow's
/// GhostButton/FilledButton) rather than a hand-rolled press-tracking gesture.
private struct ShareCardButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .semibold))
                Text("Save a stats card")
            }
        }
        .buttonStyle(ShareCardButtonStyle())
    }
}

private struct ShareCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background((hovered ? WarbleTheme.electric : WarbleTheme.electricDeep)
                    .opacity(configuration.isPressed ? 0.7 : 1),
                    in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}
