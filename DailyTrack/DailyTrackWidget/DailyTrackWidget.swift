//
//  DailyTrackWidget.swift
//  DailyTrackWidget
//
//  Created by Isaac Kaczor on 2/4/26.
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Widget Task Item

struct WidgetTaskItem: Identifiable {
    let id: String
    let name: String
    let isCheckbox: Bool
    let isCompleted: Bool
    let ratio: Double
    let benchmark: Double
    let value: Double
    /// Derived per-day target for period-cumulative tasks (benchmark / period days);
    /// nil for plain daily tasks.
    var dailyTarget: Double? = nil
}

// MARK: - Recent Day Score (for large widget history)

struct RecentDayScore: Identifiable {
    let id: String // date string
    let label: String // short day label (e.g. "Mon")
    let score: Double
}

// MARK: - Timeline Entry

struct DailyTrackEntry: TimelineEntry {
    let date: Date
    let score: Double
    let streak: Int
    let tasks: [WidgetTaskItem]
    let recentScores: [RecentDayScore] // last 5 days (not including today)

    static var placeholder: DailyTrackEntry {
        DailyTrackEntry(
            date: Date(),
            score: 0.75,
            streak: 5,
            tasks: [
                WidgetTaskItem(id: "1", name: "Exercise", isCheckbox: true, isCompleted: true, ratio: 1.0, benchmark: 1, value: 1),
                WidgetTaskItem(id: "2", name: "Read", isCheckbox: false, isCompleted: false, ratio: 0.5, benchmark: 30, value: 15),
                WidgetTaskItem(id: "3", name: "Meditate", isCheckbox: true, isCompleted: false, ratio: 0.0, benchmark: 1, value: 0),
                WidgetTaskItem(id: "4", name: "Write", isCheckbox: false, isCompleted: false, ratio: 0.8, benchmark: 500, value: 400)
            ],
            recentScores: [
                RecentDayScore(id: "2026-02-27", label: "Thu", score: 0.9),
                RecentDayScore(id: "2026-02-28", label: "Fri", score: 0.6),
                RecentDayScore(id: "2026-03-01", label: "Sat", score: 0.85),
                RecentDayScore(id: "2026-03-02", label: "Sun", score: 0.4),
                RecentDayScore(id: "2026-03-03", label: "Mon", score: 0.72)
            ]
        )
    }
}

// MARK: - Timeline Provider

struct DailyTrackTimelineProvider: TimelineProvider {
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func placeholder(in context: Context) -> DailyTrackEntry {
        DailyTrackEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyTrackEntry) -> Void) {
        if context.isPreview {
            completion(DailyTrackEntry.placeholder)
            return
        }
        let entry = loadCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyTrackEntry>) -> Void) {
        let entry = loadCurrentEntry()

        // Refresh at midnight or in 30 minutes, whichever is sooner
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        let thirtyMinutes = Date().addingTimeInterval(30 * 60)
        let nextUpdate = min(midnight, thirtyMinutes)

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadCurrentEntry() -> DailyTrackEntry {
        do {
            let schema = Schema([TaskDefinition.self, DailyEntry.self])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: false,
                groupContainer: .identifier(AppGroupContainer.appGroupIdentifier)
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            let todayStr = dateFormatter.string(from: Date())

            // Fetch active tasks
            let taskDescriptor = FetchDescriptor<TaskDefinition>(
                predicate: #Predicate { $0.isActive == true && $0.deleted == false },
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
            )
            let tasks = (try? context.fetch(taskDescriptor)) ?? []

            // Fetch today's entries
            let entryDescriptor = FetchDescriptor<DailyEntry>(
                predicate: #Predicate { $0.date == todayStr && $0.deleted == false }
            )
            let entries = (try? context.fetch(entryDescriptor)) ?? []
            let entryMap = Dictionary(entries.compactMap { e in
                e.task.map { ($0.id, e) }
            }, uniquingKeysWith: { first, _ in first })

            // Build task items (non-cumulative + period-cumulative for widget)
            var widgetTasks: [WidgetTaskItem] = []
            var totalWeight = 0.0
            var weightedSum = 0.0
            let today = Date()

            for task in tasks where !task.isCumulative || task.hasPeriod {
                let entry = entryMap[task.id]
                let value = entry?.value ?? 0
                let ratio: Double
                var derivedDailyTarget: Double? = nil
                if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
                } else if task.hasPeriod, let pw = periodWindow(for: task, on: today) {
                    let dailyTarget = task.benchmark / Double(pw.periodDays)
                    ratio = dailyTarget > 0 ? value / dailyTarget : 0
                    derivedDailyTarget = dailyTarget
                } else {
                    ratio = task.benchmark > 0 ? value / task.benchmark : 0
                }

                widgetTasks.append(WidgetTaskItem(
                    id: task.id,
                    name: task.name,
                    isCheckbox: task.isCheckbox,
                    isCompleted: value > 0,
                    ratio: ratio,
                    benchmark: task.benchmark,
                    value: value,
                    dailyTarget: derivedDailyTarget
                ))

                totalWeight += task.weight
                weightedSum += ratio * task.weight
            }

            let score = totalWeight > 0 ? weightedSum / totalWeight : 0
            let scoringTasks = tasks.filter { !$0.isCumulative || $0.hasPeriod }
            let streak = computeStreak(context: context, tasks: scoringTasks)
            let recentScores = computeRecentScores(context: context, tasks: scoringTasks, days: 5)

            return DailyTrackEntry(
                date: Date(),
                score: score,
                streak: streak,
                tasks: widgetTasks,
                recentScores: recentScores
            )
        } catch {
            return DailyTrackEntry(date: Date(), score: 0, streak: 0, tasks: [], recentScores: [])
        }
    }

    private func computeStreak(context: ModelContext, tasks: [TaskDefinition], threshold: Double = 0.7) -> Int {
        guard !tasks.isEmpty else { return 0 }

        let totalWeight = tasks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }

        let allEntries: [DailyEntry] = (try? context.fetch(FetchDescriptor<DailyEntry>())) ?? []

        var dateEntries: [String: [DailyEntry]] = [:]
        for entry in allEntries where !entry.deleted {
            dateEntries[entry.date, default: []].append(entry)
        }

        var dateScores: [String: Double] = [:]
        for (date, entries) in dateEntries {
            guard let entryDate = dateFormatter.date(from: date) else { continue }
            let entryMap = Dictionary(entries.compactMap { e in
                e.task.map { ($0.id, e) }
            }, uniquingKeysWith: { first, _ in first })

            var weightedSum = 0.0
            for task in tasks {
                let value = entryMap[task.id]?.value ?? 0
                let ratio: Double
                if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
                } else if task.hasPeriod, let pw = periodWindow(for: task, on: entryDate) {
                    let dailyTarget = task.benchmark / Double(pw.periodDays)
                    ratio = dailyTarget > 0 ? value / dailyTarget : 0
                } else {
                    ratio = task.benchmark > 0 ? value / task.benchmark : 0
                }
                weightedSum += ratio * task.weight
            }
            dateScores[date] = weightedSum / totalWeight
        }

        var streak = 0
        var expectedDate = Calendar.current.startOfDay(for: Date())
        while true {
            let dateStr = dateFormatter.string(from: expectedDate)
            guard let score = dateScores[dateStr], score >= threshold else { break }
            streak += 1
            expectedDate = Calendar.current.date(byAdding: .day, value: -1, to: expectedDate)!
        }
        return streak
    }

    private func computeRecentScores(context: ModelContext, tasks: [TaskDefinition], days: Int) -> [RecentDayScore] {
        guard !tasks.isEmpty else { return [] }

        let totalWeight = tasks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let dayLabelFormatter = DateFormatter()
        dayLabelFormatter.dateFormat = "EEE" // e.g. "Mon"

        let allEntries: [DailyEntry] = (try? context.fetch(FetchDescriptor<DailyEntry>())) ?? []
        var dateEntries: [String: [DailyEntry]] = [:]
        for entry in allEntries where !entry.deleted {
            dateEntries[entry.date, default: []].append(entry)
        }

        var results: [RecentDayScore] = []
        for offset in (1...days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = dateFormatter.string(from: date)
            let label = dayLabelFormatter.string(from: date)

            let entries = dateEntries[dateStr] ?? []
            let entryMap = Dictionary(entries.compactMap { e in
                e.task.map { ($0.id, e) }
            }, uniquingKeysWith: { first, _ in first })

            var weightedSum = 0.0
            for task in tasks {
                let value = entryMap[task.id]?.value ?? 0
                let ratio: Double
                if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
                } else if task.hasPeriod, let pw = periodWindow(for: task, on: date) {
                    let dailyTarget = task.benchmark / Double(pw.periodDays)
                    ratio = dailyTarget > 0 ? value / dailyTarget : 0
                } else {
                    ratio = task.benchmark > 0 ? value / task.benchmark : 0
                }
                weightedSum += ratio * task.weight
            }

            let score = weightedSum / totalWeight
            results.append(RecentDayScore(id: dateStr, label: label, score: score))
        }

        return results
    }

}

// MARK: - Score Ring View

struct ScoreRingView: View {
    let score: Double
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.divider, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(score, 1.0))
                .stroke(
                    Theme.scoreColor(score),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: score)

            Text("\(Int(score * 100))%")
                .font(Theme.displaySemiBold(size * 0.25))
                .foregroundStyle(Theme.scoreColor(score))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Streak View

struct StreakView: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .foregroundStyle(streak > 0 ? Theme.terra : Theme.inkTertiary)
            Text("\(streak)")
                .font(Theme.monoMedium(12))
                .foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: WidgetTaskItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            if task.isCheckbox {
                Button(intent: ToggleTaskIntent(taskId: task.id)) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isCompleted ? Theme.positive : Theme.inkTertiary)
                        .font(.system(size: compact ? 16 : 20))
                }
                .buttonStyle(.plain)
            } else {
                ProgressCircle(ratio: task.ratio, size: compact ? 16 : 20)
            }

            Text(task.name)
                .font(Theme.bodyMedium(compact ? 12 : 14))
                .lineLimit(1)
                .foregroundStyle(Theme.ink)

            Spacer()

            if !task.isCheckbox && !compact {
                // Period tasks show progress against the derived daily target,
                // not the full period benchmark (e.g. "1.5/2.8", not "0/87").
                let target = task.dailyTarget ?? task.benchmark
                Text("\(formatShort(task.value))/\(formatShort(target))")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func formatShort(_ n: Double) -> String {
        if n == n.rounded() { return String(Int(n)) }
        return String(format: "%.1f", n)
    }
}

struct ProgressCircle: View {
    let ratio: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.divider, lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(ratio, 1.0))
                .stroke(Theme.scoreColor(ratio), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: DailyTrackEntry

    var body: some View {
        VStack(spacing: 8) {
            ScoreRingView(score: entry.score, size: 80, lineWidth: 8)

            StreakView(streak: entry.streak)
        }
        .containerBackground(Theme.background, for: .widget)
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: DailyTrackEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                ScoreRingView(score: entry.score, size: 70, lineWidth: 6)
                StreakView(streak: entry.streak)
            }
            .frame(width: 90)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.tasks.prefix(4)) { task in
                    TaskRowView(task: task, compact: true)
                }

                if entry.tasks.isEmpty {
                    Text("No tasks for today")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .containerBackground(Theme.background, for: .widget)
    }
}

// MARK: - Day Score Bar View

struct DayScoreBar: View {
    let day: RecentDayScore
    let maxHeight: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(day.score * 100))%")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.inkSecondary)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.panel)
                    .frame(width: 28, height: maxHeight)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.scoreColor(day.score))
                    .frame(width: 28, height: max(2, maxHeight * min(day.score, 1.0)))
            }

            Text(day.label)
                .font(Theme.bodyMedium(11))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

// MARK: - Large Widget View

struct LargeWidgetView: View {
    let entry: DailyTrackEntry

    var body: some View {
        VStack(spacing: 16) {
            // Today's progress section
            VStack(spacing: 8) {
                Text("Today's Progress")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSecondary)

                ScoreRingView(score: entry.score, size: 100, lineWidth: 9)

                StreakView(streak: entry.streak)
            }

            Divider()

            // Last 5 days section
            VStack(spacing: 8) {
                Text("Last 5 Days")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSecondary)

                if entry.recentScores.isEmpty {
                    Text("No history yet")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxHeight: .infinity)
                } else {
                    HStack(spacing: 12) {
                        ForEach(entry.recentScores) { day in
                            DayScoreBar(day: day, maxHeight: 80)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(Theme.background, for: .widget)
    }
}

// MARK: - Widget Configuration

struct DailyTrackWidget: Widget {
    let kind: String = "DailyTrackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyTrackTimelineProvider()) { entry in
            DailyTrackWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DailyTrack")
        .description("Track your daily progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DailyTrackWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: DailyTrackEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Bundle

@main
struct DailyTrackWidgetBundle: WidgetBundle {
    init() {
        // Register bundled design-system fonts in the extension process
        FontRegistration.registerBundledFonts()
    }

    var body: some Widget {
        DailyTrackWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    DailyTrackWidget()
} timeline: {
    DailyTrackEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    DailyTrackWidget()
} timeline: {
    DailyTrackEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    DailyTrackWidget()
} timeline: {
    DailyTrackEntry.placeholder
}
