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

            // Fetch all entries once; today's rows, streak, and recent scores share the index
            let allEntries: [DailyEntry] = (try? context.fetch(FetchDescriptor<DailyEntry>())) ?? []
            var dateEntries: [String: [DailyEntry]] = [:]
            for entry in allEntries where !entry.deleted {
                dateEntries[entry.date, default: []].append(entry)
            }

            let entries = dateEntries[todayStr] ?? []
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
                if task.hasPeriod, let pw = periodWindow(for: task, on: today) {
                    let dailyTarget = task.benchmark / Double(pw.periodDays)
                    ratio = dailyTarget > 0 ? value / dailyTarget : 0
                    derivedDailyTarget = dailyTarget
                } else if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
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
            let streak = computeStreak(dateEntries: dateEntries, tasks: scoringTasks)
            let recentScores = computeRecentScores(dateEntries: dateEntries, tasks: scoringTasks, days: 5)

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

    private func computeStreak(dateEntries: [String: [DailyEntry]], tasks: [TaskDefinition], threshold: Double = 0.7) -> Int {
        guard !tasks.isEmpty else { return 0 }

        let totalWeight = tasks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }

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
                if task.hasPeriod, let pw = periodWindow(for: task, on: entryDate) {
                    let dailyTarget = task.benchmark / Double(pw.periodDays)
                    ratio = dailyTarget > 0 ? value / dailyTarget : 0
                } else if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
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

    private func computeRecentScores(dateEntries: [String: [DailyEntry]], tasks: [TaskDefinition], days: Int) -> [RecentDayScore] {
        guard !tasks.isEmpty else { return [] }

        let totalWeight = tasks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let dayLabelFormatter = DateFormatter()
        dayLabelFormatter.dateFormat = "EEE" // e.g. "Mon"

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
                if task.hasPeriod, let pw = periodWindow(for: task, on: date) {
                    let dailyTarget = task.benchmark / Double(pw.periodDays)
                    ratio = dailyTarget > 0 ? value / dailyTarget : 0
                } else if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
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

// MARK: - Shared widget pieces

/// Score block: eyebrow, big tabular score, meter.
struct ScoreBlock: View {
    let score: Double
    var valueSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(String(localized: "Today"))

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int(score * 100))")
                    .font(Theme.monoMedium(valueSize))
                    .foregroundStyle(Theme.scoreColor(score))
                Text("%")
                    .font(Theme.mono(valueSize * 0.45))
                    .foregroundStyle(Theme.inkSecondary)
            }

            MeterBar(ratio: score, height: 3)
        }
    }
}

/// Mono streak stamp, quiet when zero.
struct StreakStamp: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9))
                .foregroundStyle(streak > 0 ? Theme.terra : Theme.inkTertiary)
            Text("\(streak)")
                .font(Theme.monoMedium(11))
                .foregroundStyle(streak > 0 ? Theme.ink : Theme.inkTertiary)
        }
    }
}

// MARK: - Task Row View

struct WidgetTaskRow: View {
    let task: WidgetTaskItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            if task.isCheckbox {
                Button(intent: ToggleTaskIntent(taskId: task.id)) {
                    SquareCheckGlyph(isOn: task.isCompleted, size: compact ? 13 : 15)
                }
                .buttonStyle(.plain)
            } else {
                SquareGauge(ratio: task.ratio, size: compact ? 13 : 15)
            }

            Text(task.name)
                .font(Theme.body(compact ? 12 : 13))
                .lineLimit(1)
                .foregroundStyle(Theme.ink)

            Spacer(minLength: 4)

            if !task.isCheckbox {
                // Period tasks show progress against the derived daily target,
                // not the full period benchmark (e.g. "1.5/2.8", not "0/87").
                let target = task.dailyTarget ?? task.benchmark
                Text("\(decimalString(task.value))/\(decimalString(target))")
                    .font(Theme.mono(compact ? 10 : 11))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: DailyTrackEntry

    private var completed: Int {
        entry.tasks.filter { $0.ratio >= 1.0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ScoreBlock(score: entry.score, valueSize: 34)
                Spacer()
            }

            Spacer(minLength: 8)

            Hairline()

            HStack {
                Text("\(completed)/\(entry.tasks.count)")
                    .font(Theme.monoMedium(11))
                    .foregroundStyle(Theme.ink)
                + Text(" \(String(localized: "Completed"))")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.inkTertiary)

                Spacer()

                StreakStamp(streak: entry.streak)
            }
            .padding(.top, 8)
        }
        .containerBackground(for: .widget) { GrainTile() }
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: DailyTrackEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                ScoreBlock(score: entry.score, valueSize: 30)
                Spacer(minLength: 4)
                StreakStamp(streak: entry.streak)
            }
            .frame(width: 96, alignment: .leading)

            Hairline(vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(entry.tasks.prefix(4)) { task in
                    WidgetTaskRow(task: task, compact: true)
                }

                if entry.tasks.isEmpty {
                    Text(String(localized: "No tasks for today"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(for: .widget) { GrainTile() }
    }
}

// MARK: - Day Score Bar View

struct DayScoreBar: View {
    let day: RecentDayScore
    let maxHeight: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Int(day.score * 100))")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.inkSecondary)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.panel)

                Rectangle()
                    .fill(Theme.scoreColor(day.score))
                    .frame(height: max(2, maxHeight * min(day.score, 1.0)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .frame(height: maxHeight)

            Eyebrow(day.label, size: 8)
        }
    }
}

// MARK: - Large Widget View

struct LargeWidgetView: View {
    let entry: DailyTrackEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ScoreBlock(score: entry.score, valueSize: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StreakStamp(streak: entry.streak)
            }

            Hairline()

            // Task ledger
            VStack(alignment: .leading, spacing: 7) {
                ForEach(entry.tasks.prefix(6)) { task in
                    WidgetTaskRow(task: task, compact: false)
                }

                if entry.tasks.isEmpty {
                    Text(String(localized: "No tasks for today"))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Hairline()

            // Last 5 days
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(String(localized: "Last 5 days"), size: 9)

                if entry.recentScores.isEmpty {
                    Text(String(localized: "No history yet"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(entry.recentScores) { day in
                            DayScoreBar(day: day, maxHeight: 36)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .containerBackground(for: .widget) { GrainTile() }
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
