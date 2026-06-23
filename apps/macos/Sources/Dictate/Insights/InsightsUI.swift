import SwiftUI
import AppKit

/// The Insights dashboard shell: a Flow-style dark sidebar (Home / Insights / Dictionary / History)
/// over a detail pane. Phase 1 wires Home to real stats; the others are honest placeholders.
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
}

struct InsightsRootView: View {
    @ObservedObject var store: InsightStore
    @ObservedObject var nav: InsightsNav

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.section) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(VozTheme.electric)
                    Text("voz").font(.headline).foregroundStyle(VozTheme.textHi)
                    Text("Insights").font(.headline).foregroundStyle(VozTheme.mist)
                }
                .padding(.vertical, 8)

                ForEach(InsightsSection.allCases) { s in
                    Label(s.rawValue, systemImage: s.icon).tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 260)
        } detail: {
            Group {
                switch nav.section {
                case .home: HomeView(store: store)
                case .insights: InsightsView(store: store)
                case .dictionary: DictionaryView()
                case .history: HistoryView(store: store)
                case .data: DataPrivacyView(store: store)
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            .background(VozTheme.black)
        }
        .preferredColorScheme(.dark)
        .overlay { if nav.showTutorial { TutorialOverlay(nav: nav) } }
    }
}

/// A short, skippable walkthrough of the dashboard — shown once, right after engine setup finishes.
/// Each step switches the detail pane to the section it describes, so you see it behind the card.
struct TutorialOverlay: View {
    @ObservedObject var nav: InsightsNav
    @State private var step = 0

    private struct Step { let title: String; let body: String; let section: InsightsSection; let icon: String }
    private let steps: [Step] = [
        .init(title: "This is your dashboard", body: "Everything voz records and learns lives here — and only here, on your Mac.", section: .home, icon: "square.grid.2x2"),
        .init(title: "History", body: "Every dictation, searchable. Open one to replay the audio, fix the text, or teach voz a word.", section: .history, icon: "clock.arrow.circlepath"),
        .init(title: "Dictionary", body: "Your learned spellings and read-aloud pronunciations — voz gets them right next time.", section: .dictionary, icon: "character.book.closed"),
        .init(title: "Insights", body: "Trends over time: words per day, speaking pace, and where you dictate most.", section: .insights, icon: "chart.bar"),
        .init(title: "Data & Privacy", body: "You're in control — keep history or not, save recordings or not, skip password fields. Nothing ever leaves your Mac.", section: .data, icon: "lock.shield"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: steps[step].icon).font(.system(size: 18, weight: .medium)).foregroundStyle(VozTheme.electric)
                    Text(steps[step].title).font(.system(size: 18, weight: .semibold)).foregroundStyle(VozTheme.textHi)
                    Spacer()
                    Button("Skip") { finish() }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(VozTheme.mist)
                }
                Text(steps[step].body).font(.system(size: 13)).foregroundStyle(VozTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle().fill(i == step ? VozTheme.electric : VozTheme.line).frame(width: 6, height: 6)
                    }
                    Spacer()
                    if step > 0 {
                        Button("Back") { withAnimation { step -= 1; nav.section = steps[step].section } }
                            .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(VozTheme.mist)
                    }
                    Button(step == steps.count - 1 ? "Done" : "Next") { advance() }.buttonStyle(TutorialButton())
                }
                .padding(.top, 4)
            }
            .padding(22).frame(width: 410)
            .background(RoundedRectangle(cornerRadius: 16).fill(VozTheme.ink))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(VozTheme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 28, y: 12)
        }
        .onAppear { nav.section = steps[0].section }
    }

    private func advance() {
        if step < steps.count - 1 { withAnimation { step += 1; nav.section = steps[step].section } } else { finish() }
    }
    private func finish() {
        UserDefaults.standard.set(true, forKey: "didShowTutorial")
        withAnimation { nav.showTutorial = false }
    }
}

private struct TutorialButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(VozTheme.electric.opacity(configuration.isPressed ? 0.7 : 1)))
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
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome back, \(firstName)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(VozTheme.textHi)

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
                        .foregroundStyle(VozTheme.mist)
                        .textCase(.uppercase)
                    VStack(spacing: 0) {
                        ForEach(store.events.suffix(8).reversed()) { e in
                            RecentRow(event: e)
                            if e.id != store.events.suffix(8).reversed().last?.id {
                                Divider().overlay(VozTheme.line)
                            }
                        }
                    }
                    .background(VozTheme.ink, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(VozTheme.line, lineWidth: 1))

                    if !store.perApp.isEmpty {
                        Text("Where you dictate")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VozTheme.mist).textCase(.uppercase)
                            .padding(.top, 8)
                        let maxWords = store.perApp.first?.words ?? 1
                        VStack(spacing: 12) {
                            ForEach(store.perApp.prefix(5)) { app in
                                PerAppRow(app: app, maxWords: maxWords)
                            }
                        }
                        .padding(16)
                        .background(VozTheme.ink, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VozTheme.line, lineWidth: 1))
                    }
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VozTheme.black)
    }
}

struct PerAppRow: View {
    let app: InsightStore.AppUsage
    let maxWords: Int
    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleId: app.id, size: 18)
            Text(app.name).font(.system(size: 12)).foregroundStyle(VozTheme.textHi)
                .frame(width: 120, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(VozTheme.line)
                    Capsule().fill(VozTheme.electric)
                        .frame(width: max(6, geo.size.width * CGFloat(app.words) / CGFloat(max(1, maxWords))))
                }
            }
            .frame(height: 8)
            Text("\(app.words)").font(.system(size: 11)).foregroundStyle(VozTheme.mist)
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
                .foregroundStyle(VozTheme.textHi)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(VozTheme.mist)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VozTheme.ink, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(VozTheme.line, lineWidth: 1))
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
                .foregroundStyle(VozTheme.mist)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.text.isEmpty ? "\(event.words) words" : event.text)
                    .font(.system(size: 13))
                    .foregroundStyle(VozTheme.textHi)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let app = event.appName {
                        Text(app).font(.system(size: 11)).foregroundStyle(VozTheme.electric)
                    }
                    Text("· \(event.words) words · \(event.wpm) wpm")
                        .font(.system(size: 11))
                        .foregroundStyle(VozTheme.mist)
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
            Image(systemName: "mic").font(.system(size: 28)).foregroundStyle(VozTheme.electric)
            Text("Hold Fn and start dictating — your words, streak, and WPM build up here.")
                .font(.system(size: 13))
                .foregroundStyle(VozTheme.mist)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(VozTheme.ink, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VozTheme.line, lineWidth: 1))
    }
}

struct ComingSoon: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(VozTheme.electric)
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(VozTheme.textHi)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(VozTheme.mist)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Text("Coming soon").font(.system(size: 11, weight: .semibold)).foregroundStyle(VozTheme.mist)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
