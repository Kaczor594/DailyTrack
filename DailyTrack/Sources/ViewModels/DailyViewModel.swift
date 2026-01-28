import Foundation
import SwiftUI

/// Main view model managing daily task data and interactions.
@Observable
final class DailyViewModel {
    var selectedDate: Date = Date()
    var taskProgressList: [TaskProgress] = []
    var dailyScore: Double = 0
    var currentStreak: Int = 0

    private let db = DatabaseManager.shared
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

    func loadData() {
        let tasks = db.fetchAllTasks()
        let entries = db.fetchEntries(for: selectedDateString)
        let entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.taskId, $0) })

        taskProgressList = tasks.map { task in
            let entry = entryMap[task.id] ?? DailyEntry(taskId: task.id, date: selectedDateString)
            let cumTotal = task.isCumulative ? db.cumulativeTotal(forTask: task.id) : nil
            return TaskProgress(task: task, entry: entry, cumulativeTotal: cumTotal)
        }

        calculateDailyScore()
        currentStreak = db.currentStreak()
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
                ratio = min(progress.dailyRatio, 1.0)
            }
            return sum + ratio * progress.task.weight
        }

        dailyScore = weightedSum / totalWeight
    }

    // MARK: - Entry Updates

    func updateValue(for taskId: String, value: Double) {
        guard let idx = taskProgressList.firstIndex(where: { $0.task.id == taskId }) else { return }
        taskProgressList[idx].entry.value = value
        db.upsertEntry(taskProgressList[idx].entry)

        // Refresh cumulative total if needed
        if taskProgressList[idx].task.isCumulative {
            taskProgressList[idx].cumulativeTotal = db.cumulativeTotal(forTask: taskId)
        }

        calculateDailyScore()
        currentStreak = db.currentStreak()
    }

    func toggleCheckbox(for taskId: String) {
        guard let idx = taskProgressList.firstIndex(where: { $0.task.id == taskId }) else { return }
        let newValue: Double = taskProgressList[idx].entry.value > 0 ? 0 : 1
        updateValue(for: taskId, value: newValue)
    }

    // MARK: - Navigation

    func goToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        loadData()
    }

    func goToNextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        loadData()
    }

    func goToToday() {
        selectedDate = Date()
        loadData()
    }
}
