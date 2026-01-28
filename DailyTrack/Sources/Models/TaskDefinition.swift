import Foundation

/// A task that can be tracked daily or cumulatively.
struct TaskDefinition: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var benchmark: Double          // Target value per day (e.g., 4 hours, 1 workout)
    var unit: String               // Display unit (e.g., "Stunde", "Bewerbung")
    var weight: Double             // Weight toward daily total score (e.g., 0.2 = 20%)
    var isCumulative: Bool         // If true, tracks progress toward a total goal over time
    var isCheckbox: Bool           // If true, task is simple done/not-done
    var sortOrder: Int
    var isActive: Bool
    var createdAt: String

    init(
        id: String = UUID().uuidString,
        name: String,
        benchmark: Double = 1.0,
        unit: String = "",
        weight: Double = 1.0,
        isCumulative: Bool = false,
        isCheckbox: Bool = false,
        sortOrder: Int = 0,
        isActive: Bool = true,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.name = name
        self.benchmark = benchmark
        self.unit = unit
        self.weight = weight
        self.isCumulative = isCumulative
        self.isCheckbox = isCheckbox
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
