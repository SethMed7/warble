import SwiftUI
import Charts

/// The Insights charts — words per day, speaking pace (WPM), and per-app usage. All derived from the
/// local store, single electric-blue hue (no rainbow), dark axes. Charts sit directly on the window
/// background: a 13pt header with an 11pt trailing range label, no boxes.
struct InsightsView: View {
    @ObservedObject var store: InsightStore
    @ObservedObject var ai: AIInsightsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Insights AI sits above the charts and shows even with no dictations yet (so the
                // opt-in enable section is reachable). The charts below stay gated on having data.
                AIInsightsView(ai: ai, store: store)
                Hairline().padding(.vertical, 24)
                if store.dictations.isEmpty {
                    EmptyState(title: "No trends yet",
                               hint: "Hold Fn and speak — words per day, pace, and top apps chart here.")
                } else {
                    section("Words per day", "Last 30 days") { wordsChart }
                    Hairline().padding(.vertical, 24)
                    section("Speaking pace", "Words per minute, by day") { wpmChart }
                    Hairline().padding(.vertical, 24)
                    section("Where you dictate", "Words by app") { perAppChart }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
        .onAppear { ai.refreshIfNeeded() }   // fire the auto path when the tab opens
    }

    private var wordsChart: some View {
        Chart(store.wordsPerDay) { d in
            BarMark(x: .value("Day", d.date, unit: .day), y: .value("Words", d.value), width: .fixed(6))
                .foregroundStyle(WarbleTheme.electric)
                .cornerRadius(2)
        }
        .frame(height: 170)
        .chartXAxis { dayAxis }
        .chartYAxis { valueAxis }
    }

    private var wpmChart: some View {
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

    private var perAppChart: some View {
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

    /// A chart block: the section header carries the range as a trailing data label, then the chart.
    private func section<C: View>(_ title: String, _ meta: String, @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
                Spacer(minLength: 0)
                Text(meta).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
            }
            chart()
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
