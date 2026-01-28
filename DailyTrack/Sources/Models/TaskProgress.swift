import Foundation

/// Combined view of a task definition with its entry for a specific day.
/// Used by the UI to display task rows with progress.
struct TaskProgress: Identifiable {
    let task: TaskDefinition
    var entry: DailyEntry
    var cumulativeTotal: Double?    // Only set for cumulative tasks

    var id: String { task.id }

    /// Completion ratio for today's entry
    var dailyRatio: Double {
        entry.completionRatio(benchmark: task.benchmark)
    }

    /// Formatted display of daily progress
    var dailyProgressText: String {
        if task.isCheckbox {
            return entry.value > 0 ? String(localized: "Done") : String(localized: "Not done")
        }
        let valueStr = formatNumber(entry.value)
        let benchStr = formatNumber(task.benchmark)
        return "\(valueStr) / \(benchStr) \(task.unit)"
    }

    /// Cumulative progress as percentage toward benchmark * total days (for cumulative tasks)
    var cumulativeRatio: Double? {
        guard task.isCumulative, let total = cumulativeTotal else { return nil }
        guard task.benchmark > 0 else { return 0 }
        return total / task.benchmark
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() {
            return String(Int(n))
        }
        return String(format: "%.1f", n)
    }
}
