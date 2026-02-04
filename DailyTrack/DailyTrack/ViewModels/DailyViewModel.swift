import Foundation
import SwiftUI
import SwiftData

/// Main view model managing daily task data and interactions.
@Observable
final class DailyViewModel {
    var selectedDate: Date = Date()
    var taskProgressList: [TaskProgress] = []
    var dailyScore: Double = 0
    var currentStreak: Int = 0

    private var modelContext: ModelContext?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var selectedDateString: String {
        dateFormatter.string(from: selectedDate)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var displayDate: String {
        if isToday {
            return String(localized: "Today")
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: selectedDate)
    }

    // MARK: - Data Loading

    func loadData(context: ModelContext) {
        self.modelContext = context

        let tasks = fetchActiveTasks(context: context)
        let dateStr = selectedDateString
        let entries = fetchEntries(for: dateStr, context: context)
        let entryMap = Dictionary(entries.compactMap { e in
            e.task.map { ($0.id, e) }
        }, uniquingKeysWith: { first, _ in first })

        taskProgressList = tasks.map { task in
            let entry = entryMap[task.id] ?? {
                let entryId = "\(task.id)-\(dateStr)"
                let newEntry = DailyEntry(id: entryId, task: task, date: dateStr)
                context.insert(newEntry)
                return newEntry
            }()
            let cumTotal = task.isCumulative ? cumulativeTotal(for: task, context: context) : nil
            return TaskProgress(task: task, entry: entry, cumulativeTotal: cumTotal)
        }

        try? context.save()
        calculateDailyScore()
        currentStreak = computeCurrentStreak(context: context)
    }

    private func fetchActiveTasks(context: ModelContext) -> [TaskDefinition] {
        var descriptor = FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.isActive == true && $0.deleted == false },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchEntries(for date: String, context: ModelContext) -> [DailyEntry] {
        var descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.date == date && $0.deleted == false }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func cumulativeTotal(for task: TaskDefinition, context: ModelContext) -> Double {
        let taskId = task.id
        var descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { entry in entry.task?.id == taskId }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.reduce(0) { $0 + $1.value }
    }

    func calculateDailyScore() {
        let dailyTasks = taskProgressList.filter { !$0.task.isCumulative }
        let totalWeight = dailyTasks.reduce(0.0) { $0 + $1.task.weight }
        guard totalWeight > 0 else {
            dailyScore = 0
            return
        }

        let weightedSum = dailyTasks.reduce(0.0) { sum, progress in
            let ratio: Double
            if progress.task.isCheckbox {
                ratio = progress.entry.value > 0 ? 1.0 : 0.0
            } else {
                ratio = progress.dailyRatio
            }
            return sum + ratio * progress.task.weight
        }

        dailyScore = weightedSum / totalWeight
    }

    // MARK: - Entry Updates

    func updateValue(for taskId: String, value: Double) {
        guard let context = modelContext else { return }
        guard let idx = taskProgressList.firstIndex(where: { $0.task.id == taskId }) else { return }
        taskProgressList[idx].entry.value = value
        taskProgressList[idx].entry.markUpdated()
        try? context.save()

        if taskProgressList[idx].task.isCumulative {
            taskProgressList[idx].cumulativeTotal = cumulativeTotal(for: taskProgressList[idx].task, context: context)
        }

        calculateDailyScore()
        currentStreak = computeCurrentStreak(context: context)
    }

    func toggleCheckbox(for taskId: String) {
        guard let idx = taskProgressList.firstIndex(where: { $0.task.id == taskId }) else { return }
        let newValue: Double = taskProgressList[idx].entry.value > 0 ? 0 : 1
        updateValue(for: taskId, value: newValue)
    }

    // MARK: - Navigation

    func goToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        if let ctx = modelContext { loadData(context: ctx) }
    }

    func goToNextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        if let ctx = modelContext { loadData(context: ctx) }
    }

    func goToToday() {
        selectedDate = Date()
        if let ctx = modelContext { loadData(context: ctx) }
    }

    // MARK: - Streak Calculation

    private func computeCurrentStreak(context: ModelContext, threshold: Double = 0.7) -> Int {
        let allTasks = fetchActiveTasks(context: context)
        let nonCumulativeTasks = allTasks.filter { !$0.isCumulative }
        guard !nonCumulativeTasks.isEmpty else { return 0 }

        let totalWeight = nonCumulativeTasks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }

        // Fetch all entries
        let allEntries: [DailyEntry] = (try? context.fetch(FetchDescriptor<DailyEntry>())) ?? []

        // Group by date
        var dateEntries: [String: [DailyEntry]] = [:]
        for entry in allEntries {
            dateEntries[entry.date, default: []].append(entry)
        }

        // Compute score per date
        var dateScores: [String: Double] = [:]
        for (date, entries) in dateEntries {
            let entryMap = Dictionary(entries.compactMap { e in
                e.task.map { ($0.id, e) }
            }, uniquingKeysWith: { first, _ in first })
            var weightedSum = 0.0
            for task in nonCumulativeTasks {
                let value = entryMap[task.id]?.value ?? 0
                let ratio: Double
                if task.isCheckbox {
                    ratio = value > 0 ? 1.0 : 0.0
                } else {
                    ratio = task.benchmark > 0 ? min(value / task.benchmark, 1.0) : 0
                }
                weightedSum += ratio * task.weight
            }
            dateScores[date] = weightedSum / totalWeight
        }

        // Walk backwards from today
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
}
