import SwiftUI
import Charts

/// The Insights charts — words per day, speaking pace (WPM), and per-app usage. All derived from the
/// local store, single electric-blue hue (no rainbow), dark axes.
struct InsightsView: View {
    @ObservedObject var store: InsightStore
    @ObservedObject var ai: AIInsightsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Insights",
                           subtitle: "Trends over the last 30 days — volume, pace, and where you dictate.")
                // Insights AI sits above the charts and shows even with no dictations yet (so the
                // opt-in enable card is reachable). The charts below stay gated on having data.
                AIInsightsView(ai: ai, store: store)
                if store.dictations.isEmpty {
                    EmptyState(icon: "chart.bar", title: "No trends yet",
                               message: "Dictate a few times — words per day, speaking pace, and your top apps chart here. Hold Fn and speak.")
                } else {
                    wordsCard
                    wpmCard
                    perAppCard
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
        .onAppear { ai.refreshIfNeeded() }   // fire the auto path when the tab opens
    }

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Words per day", "Last 30 days")
            Chart(store.wordsPerDay) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Words", d.value), width: .fixed(6))
                    .foregroundStyle(WarbleTheme.electric)
                    .cornerRadius(2)
            }
            .frame(height: 170)
            .chartXAxis { dayAxis }
            .chartYAxis { valueAxis }
        }
        .cardStyle()
    }

    private var wpmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Speaking pace", "Words per minute, by day")
            Chart(store.wpmPerDay) { d in
                AreaMark(x: .value("Day", d.date, unit: .day), y: .value("WPM", d.value))
                    .foregroundStyle(LinearGradient(colors: [WarbleTheme.electric.opacity(0.30), WarbleTheme.electric.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", d.date, unit: .day), y: .value("WPM", d.value))
                    .foregroundStyle(WarbleTheme.electric)
                    .interpolationMethod(.catmullRom)
            }
            .frame(height: 170)
            .chartXAxis { dayAxis }
            .chartYAxis { valueAxis }
        }
        .cardStyle()
    }

    private var perAppCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Where you dictate", "Words by app")
            Chart(Array(store.perApp.prefix(8))) { app in
                BarMark(x: .value("Words", app.words), y: .value("App", app.name))
                    .foregroundStyle(WarbleTheme.electric)
                    .cornerRadius(3)
            }
            .frame(height: CGFloat(min(8, max(1, store.perApp.count)) * 32 + 24))
            .chartXAxis { valueAxis }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(WarbleTheme.mist).font(.system(size: 11)) }
            }
        }
        .cardStyle()
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(WarbleTheme.mist)
        }
    }

    private var dayAxis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(WarbleTheme.line.opacity(0.6))
            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(WarbleTheme.mist).font(.system(size: 10))
        }
    }
    private var valueAxis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(WarbleTheme.line.opacity(0.5))
            AxisValueLabel().foregroundStyle(WarbleTheme.mist).font(.system(size: 10))
        }
    }
}
