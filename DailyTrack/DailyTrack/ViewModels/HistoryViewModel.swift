import Foundation

/// View model for the history and analytics views.
@Observable
final class HistoryViewModel {
    var dailyScores: [(date: String, score: Double)] = []
    var taskHistory: [String: [DailyEntry]] = [:]  // taskId -> entries
    var tasks: [TaskDefinition] = []
    var selectedPeriod: Period = .month
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var averageScore: Double = 0
    var totalDaysTracked: Int = 0

    enum Period: String, CaseIterable {
        case week, month, quarter, year

        var displayName: String {
            switch self {
            case .week: return String(localized: "Week")
            case .month: return String(localized: "Month")
            case .quarter: return String(localized: "Quarter")
            case .year: return String(localized: "Year")
            }
        }

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            }
        }
    }

    private let db = DatabaseManager.shared
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func loadData() {
        tasks = db.fetchAllTasks()

        let endDate = dateFormatter.string(from: Date())
        let startDate = dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: -selectedPeriod.days, to: Date())!
        )

        dailyScores = db.dailyScores(from: startDate, to: endDate)
        currentStreak = db.currentStreak()

        // Calculate stats
        if !dailyScores.isEmpty {
            averageScore = dailyScores.reduce(0) { $0 + $1.score } / Double(dailyScores.count)
            totalDaysTracked = dailyScores.count
        }

        // Load per-task history
        for task in tasks {
            taskHistory[task.id] = db.fetchEntries(forTask: task.id)
        }

        // Calculate best streak
        bestStreak = calculateBestStreak()
    }

    private func calculateBestStreak() -> Int {
        var best = 0
        var current = 0
        let threshold = 0.7

        let sorted = dailyScores.sorted { $0.date < $1.date }
        var previousDate: Date?

        for entry in sorted {
            guard let date = dateFormatter.date(from: entry.date) else { continue }

            if let prev = previousDate {
                let dayDiff = Calendar.current.dateComponents([.day], from: prev, to: date).day ?? 0
                if dayDiff == 1 && entry.score >= threshold {
                    current += 1
                } else if entry.score >= threshold {
                    current = 1
                } else {
                    current = 0
                }
            } else if entry.score >= threshold {
                current = 1
            }

            best = max(best, current)
            previousDate = date
        }
        return best
    }

    /// Calendar heatmap data: date string -> score (0 to 1)
    func heatmapData() -> [String: Double] {
        Dictionary(uniqueKeysWithValues: dailyScores.map { ($0.date, $0.score) })
    }

    /// Per-task scores for a given date
    func taskScores(for date: String) -> [(task: TaskDefinition, value: Double, ratio: Double)] {
        let entries = db.fetchEntries(for: date)
        let entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.taskId, $0) })

        return tasks.map { task in
            let value = entryMap[task.id]?.value ?? 0
            let ratio = task.benchmark > 0 ? value / task.benchmark : 0
            return (task, value, ratio)
        }
    }
}
