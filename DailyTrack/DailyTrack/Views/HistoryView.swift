import SwiftUI
import SwiftData
import Charts

/// History view: KPI strip, trend chart, calendar heatmap, per-day breakdown.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @State private var viewModel = HistoryViewModel()
    @State private var selectedDate: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("DailyTrack")
                        Text(String(localized: "History"))
                            .font(Theme.display(30))
                            .foregroundStyle(Theme.ink)
                    }

                    HistoryKPIStrip(
                        currentStreak: viewModel.currentStreak,
                        bestStreak: viewModel.bestStreak,
                        averageScore: viewModel.averageScore,
                        totalDays: viewModel.totalDaysTracked
                    )

                    TrendChartCard(
                        scores: viewModel.dailyScores,
                        selectedPeriod: $viewModel.selectedPeriod,
                        onPeriodChange: {
                            viewModel.loadData(context: modelContext)
                        }
                    )

                    CalendarHeatmapCard(
                        data: viewModel.heatmapData(),
                        period: viewModel.selectedPeriod,
                        onDateTap: { date in
                            selectedDate = date
                        }
                    )

                    if let date = selectedDate {
                        TaskBreakdownCard(
                            date: date,
                            scores: viewModel.taskScores(for: date)
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(PaperBackground())
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #else
            .navigationTitle(String(localized: "History"))
            #endif
            .onAppear {
                viewModel.loadData(context: modelContext)
            }
            .onChange(of: syncManager.syncVersion) { _, _ in
                viewModel.loadData(context: modelContext)
            }
        }
    }
}

// MARK: - KPI Strip

struct HistoryKPIStrip: View {
    let currentStreak: Int
    let bestStreak: Int
    let averageScore: Double
    let totalDays: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            KPIBlock(
                label: String(localized: "Streak"),
                value: "\(currentStreak)",
                unit: String(localized: "days"),
                valueColor: currentStreak > 0 ? Theme.ink : Theme.inkTertiary
            )
            Hairline(vertical: true).padding(.horizontal, 10)

            KPIBlock(
                label: String(localized: "Best Streak"),
                value: "\(bestStreak)",
                unit: String(localized: "days")
            )
            Hairline(vertical: true).padding(.horizontal, 10)

            KPIBlock(
                label: String(localized: "Average Score"),
                value: "\(Int(averageScore * 100))",
                unit: "%",
                valueColor: Theme.scoreColor(averageScore)
            )
            Hairline(vertical: true).padding(.horizontal, 10)

            KPIBlock(
                label: String(localized: "Days Tracked"),
                value: "\(totalDays)",
                unit: ""
            )

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .workbenchCard()
    }
}

// MARK: - Trend Chart

/// Chart card in the four-element structure: eyebrow + title, field, source.
struct TrendChartCard: View {
    let scores: [(date: String, score: Double)]
    @Binding var selectedPeriod: HistoryViewModel.Period
    var onPeriodChange: () -> Void

    @State private var selectedChartDate: Date?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var chartData: [(date: Date, score: Double)] {
        scores.compactMap { item in
            guard let date = dateFormatter.date(from: item.date) else { return nil }
            return (date, item.score)
        }
    }

    var selectedItem: (date: Date, score: Double)? {
        guard let selected = selectedChartDate else { return nil }
        return chartData.min(by: {
            abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(String(localized: "Trend"))
                    Text(String(localized: "Daily Completion"))
                        .font(Theme.display(19))
                        .foregroundStyle(Theme.ink)
                }

                Spacer()

                Picker(String(localized: "Period"), selection: $selectedPeriod) {
                    ForEach(HistoryViewModel.Period.allCases, id: \.self) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 190)
                .onChange(of: selectedPeriod) { _, _ in
                    onPeriodChange()
                }
            }

            if chartData.isEmpty {
                VStack(spacing: 6) {
                    Text(String(localized: "No Data Yet"))
                        .font(Theme.bodyMedium(14))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(String(localized: "Start tracking tasks to see trends here."))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(chartData, id: \.date) { item in
                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.chartMoss.opacity(0.18), Theme.chartMoss.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(Theme.chartMoss)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    if let selected = selectedItem, selected.date == item.date {
                        RuleMark(x: .value("Date", selected.date))
                            .foregroundStyle(Theme.inkTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))

                        PointMark(
                            x: .value("Date", selected.date),
                            y: .value("Score", selected.score)
                        )
                        .foregroundStyle(Theme.chartMoss)
                        .symbolSize(30)
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1.0]) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                                    .font(Theme.mono(9))
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                        }
                        AxisGridLine()
                            .foregroundStyle(Theme.divider)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.inkTertiary)
                        AxisGridLine()
                            .foregroundStyle(Theme.divider.opacity(0.5))
                    }
                }
                .chartXSelection(value: $selectedChartDate)
                .frame(height: 170)
            }

            SourceLine(text: sourceText)
        }
        .workbenchCard()
    }

    private var sourceText: String {
        if let selected = selectedItem {
            return "\(displayFormatter.string(from: selected.date)) · \(Int(selected.score * 100))%"
        }
        guard let first = chartData.first, let last = chartData.last else {
            return "n = 0"
        }
        let f = DateFormatter()
        f.dateFormat = "dd.MM."
        return "n = \(chartData.count) · \(f.string(from: first.date))–\(displayFormatter.string(from: last.date))"
    }
}

// MARK: - Calendar Heatmap

struct CalendarHeatmapCard: View {
    let data: [String: Double]
    let period: HistoryViewModel.Period
    var onDateTap: (String) -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    private var weekdaySymbols: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // grid starts on Sunday
        let symbols = cal.veryShortWeekdaySymbols // Sun-first
        return symbols
    }

    var dates: [Date?] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday = 1
        let end = Date()
        let start = cal.date(byAdding: .day, value: -period.days, to: end)!

        // Pad start to align with Sunday
        let startWeekday = cal.component(.weekday, from: start) // 1=Sun, 7=Sat
        let padCount = startWeekday - 1 // days to pad before start

        var result: [Date?] = Array(repeating: nil, count: padCount)
        var current = start
        while current <= end {
            result.append(current)
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(String(localized: "Calendar"))

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Theme.monoMedium(9))
                        .foregroundStyle(Theme.inkTertiary)
                        .textCase(.uppercase)
                }

                ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        let dateStr = dateFormatter.string(from: date)
                        let score = data[dateStr]

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.heatmapColor(score: score))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Theme.divider.opacity(score == nil ? 1 : 0), lineWidth: 1)
                            )
                            .overlay {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(Theme.mono(9))
                                    .foregroundStyle(score != nil ? Theme.heatmapLabelColor(score: score) : Theme.inkTertiary)
                            }
                            .onTapGesture {
                                onDateTap(dateStr)
                            }
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .workbenchCard()
    }
}

// MARK: - Task Breakdown

struct TaskBreakdownCard: View {
    let date: String
    let scores: [(task: TaskDefinition, value: Double, ratio: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(String(localized: "Task Breakdown — \(date)"))
                .padding(.bottom, 10)

            ForEach(Array(scores.enumerated()), id: \.element.task.id) { index, item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.task.name)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Spacer()

                    Text(formatNumber(item.value))
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.inkSecondary)

                    Text("\(Int(min(item.ratio, 1.0) * 100))%")
                        .font(Theme.monoMedium(12))
                        .foregroundStyle(Theme.scoreColor(item.ratio))
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 8)

                if index < scores.count - 1 {
                    Hairline()
                }
            }
        }
        .workbenchCard()
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() { return String(Int(n)) }
        return String(format: "%.1f", n)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [TaskDefinition.self, DailyEntry.self], inMemory: true)
}
