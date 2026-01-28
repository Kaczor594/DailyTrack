import Foundation

/// A single entry recording progress on a task for a specific day.
struct DailyEntry: Identifiable, Codable, Hashable {
    let id: String
    let taskId: String
    let date: String           // "yyyy-MM-dd" format
    var value: Double           // Actual value (hours, count, or 1.0 for checkbox)
    var notes: String?

    init(
        id: String = UUID().uuidString,
        taskId: String,
        date: String,
        value: Double = 0.0,
        notes: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.date = date
        self.value = value
        self.notes = notes
    }

    /// Completion ratio for this entry given a benchmark.
    /// Returns value/benchmark (can exceed 1.0 for daily tasks).
    func completionRatio(benchmark: Double) -> Double {
        guard benchmark > 0 else { return 0 }
        return value / benchmark
    }
}
