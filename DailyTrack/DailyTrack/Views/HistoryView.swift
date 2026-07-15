import SwiftUI
import SwiftData
import Charts

/// History view: browse past days and see trends.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @State private var viewModel = HistoryViewModel()
    @State private var selectedDate: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stats summary cards
                    StatsCardsView(
                        currentStreak: viewModel.currentStreak,
                        bestStreak: viewModel.bestStreak,
                        averageScore: viewModel.averageScore,
                        totalDays: viewModel.totalDaysTracked
                    )

                    // Period picker
                    Picker(String(localized: "Period"), selection: $viewModel.selectedPeriod) {
                        ForEach(HistoryViewModel.Period.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: viewModel.selectedPeriod) { _, _ in
                        viewModel.loadData(context: modelContext)
                    }

                    // Trend chart
                    TrendChartView(scores: viewModel.dailyScores)
                        .frame(height: 200)
                        .padding(.horizontal)

                    // Calendar heatmap
                    CalendarHeatmapView(
                        data: viewModel.heatmapData(),
                        period: viewModel.selectedPeriod,
                        onDateTap: { date in
                            selectedDate = date
                        }
                    )
                    .padding(.horizontal)

                    // Per-task breakdown (if a date is selected)
                    if let date = selectedDate {
                        TaskBreakdownView(
                            date: date,
                            scores: viewModel.taskScores(for: date)
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Theme.background)
            .navigationTitle(String(localized: "History"))
            .onAppear {
                viewModel.loadData(context: modelContext)
            }
            .onChange(of: syncManager.syncVersion) { _, _ in
                viewModel.loadData(context: modelContext)
            }
        }
    }
}

// MARK: - Stats Cards

struct StatsCardsView: View {
    let currentStreak: Int
    let bestStreak: Int
    let averageScore: Double
    let totalDays: Int

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: String(localized: "Current Streak"),
                value: "\(currentStreak)",
                unit: String(localized: "days"),
                icon: "flame.fill",
                color: Theme.terra
            )
            StatCard(
                title: String(localized: "Best Streak"),
                value: "\(bestStreak)",
                unit: String(localized: "days"),
                icon: "trophy.fill",
                color: Theme.chartDust
            )
            StatCard(
                title: String(localized: "Average Score"),
                value: "\(Int(averageScore * 100))%",
                unit: "",
                icon: "chart.bar.fill",
                color: Theme.chartSky
            )
            StatCard(
                title: String(localized: "Days Tracked"),
                value: "\(totalDays)",
                unit: "",
                icon: "calendar",
                color: Theme.brand
            )
        }
        .padding(.horizontal)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(Theme.displaySemiBold(24))
                .foregroundStyle(Theme.ink)

            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Text(title)
                .font(Theme.body(12))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }
}

// MARK: - Trend Chart

struct TrendChartView: View {
    let scores: [(date: String, score: Double)]

    @State private var selectedDate: Date?

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
        guard let selected = selectedDate else { return nil }
        return chartData.min(by: {
            abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected))
        })
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(String(localized: "Daily Completion"))
                .font(Theme.bodySemiBold(15))
                .foregroundStyle(Theme.ink)

            if chartData.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Data Yet"),
                    systemImage: "chart.line.downtrend.xyaxis",
                    description: Text(String(localized: "Start tracking tasks to see trends here."))
                )
                .frame(height: 160)
            } else {
                Chart(chartData, id: \.date) { item in
                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.chartMoss.opacity(0.25), Theme.chartMoss.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(Theme.chartMoss)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", item.date),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(Theme.chartMoss)
                    .symbolSize(20)

                    if let selected = selectedItem, selected.date == item.date {
                        RuleMark(x: .value("Date", selected.date))
                            .foregroundStyle(Theme.inkTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .annotation(position: .top, alignment: .center) {
                                VStack(spacing: 4) {
                                    Text(displayFormatter.string(from: selected.date))
                                        .font(Theme.body(11))
                                        .foregroundStyle(Theme.inkSecondary)
                                    Text("\(Int(selected.score * 100))%")
                                        .font(Theme.monoMedium(12))
                                        .foregroundStyle(Theme.ink)
                                }
                                .padding(8)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusControl)
                                        .stroke(Theme.divider, lineWidth: 1)
                                )
                            }
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXSelection(value: $selectedDate)
            }
        }
    }
}

// MARK: - Calendar Heatmap

struct CalendarHeatmapView: View {
    let data: [String: Double]
    let period: HistoryViewModel.Period
    var onDateTap: (String) -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

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
        VStack(alignment: .leading) {
            Text(String(localized: "Calendar"))
                .font(Theme.bodySemiBold(15))
                .foregroundStyle(Theme.ink)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        let dateStr = dateFormatter.string(from: date)
                        let score = data[dateStr]

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.heatmapColor(score: score))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(Theme.monoMedium(10))
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
    }

}

// MARK: - Task Breakdown

struct TaskBreakdownView: View {
    let date: String
    let scores: [(task: TaskDefinition, value: Double, ratio: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Task Breakdown — \(date)"))
                .font(Theme.bodySemiBold(15))
                .foregroundStyle(Theme.ink)

            ForEach(scores, id: \.task.id) { item in
                HStack {
                    Text(item.task.name)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.ink)

                    Spacer()

                    Text(formatNumber(item.value))
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.inkSecondary)

                    Text("\(Int(min(item.ratio, 1.0) * 100))%")
                        .font(Theme.monoMedium(11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.scoreColor(item.ratio).opacity(0.15))
                        .foregroundStyle(Theme.scoreColor(item.ratio))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
                }
            }
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.divider, lineWidth: 1)
        )
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
