import Foundation
import SwiftData

/// Seeds initial task definitions on first launch.
struct SeedData {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<TaskDefinition>()
        let existingTasks = (try? context.fetch(descriptor)) ?? []

        // Only seed if database is empty
        guard existingTasks.isEmpty else { return }

        // Reset sync timestamp so fresh seed doesn't conflict
        UserDefaults.standard.removeObject(forKey: "lastSyncTimestamp")

        // Deterministic IDs so all devices create identical tasks
        let initialTasks: [TaskDefinition] = [
            TaskDefinition(
                id: "seed-nebenprojekt",
                name: "Nebenprojekt",
                benchmark: 1.0,
                unit: NSLocalizedString("hour", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: false,
                sortOrder: 0
            ),
            TaskDefinition(
                id: "seed-aktuarwissenschaft",
                name: "Aktuarwissenschaft",
                benchmark: 1.0,
                unit: NSLocalizedString("hour", comment: ""),
                weight: 1.0,
                isCumulative: true,
                isCheckbox: false,
                sortOrder: 1
            ),
            TaskDefinition(
                id: "seed-putzen",
                name: "Putzen",
                benchmark: 1.0,
                unit: NSLocalizedString("chore", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: true,
                sortOrder: 2
            ),
            TaskDefinition(
                id: "seed-municipal-analytics",
                name: "Municipal Analytics",
                benchmark: 87.5,
                unit: NSLocalizedString("hours", comment: ""),
                weight: 4.0,
                isCumulative: true,
                cumulativePeriod: "month",
                isCheckbox: false,
                sortOrder: 4
            ),
            TaskDefinition(
                id: "seed-gc-vorbereitung",
                name: "GC Vorbereitung",
                benchmark: 1.0,
                unit: NSLocalizedString("hours", comment: ""),
                weight: 2.0,
                isCumulative: false,
                isCheckbox: false,
                sortOrder: 17
            ),
            TaskDefinition(
                id: "seed-training",
                name: "Training",
                benchmark: 1.0,
                unit: NSLocalizedString("workout", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: true,
                sortOrder: 5
            ),
            TaskDefinition(
                id: "seed-schach-lesen",
                name: "Schach/Lesen",
                benchmark: 1.0,
                unit: NSLocalizedString("game/chapter", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: false,
                sortOrder: 6
            ),
        ]

        for task in initialTasks {
            context.insert(task)
        }

        try? context.save()

        // Seed historical data
        seedHistoricalEntries(context: context)
    }

    private static func seedHistoricalEntries(context: ModelContext) {
        let descriptor = FetchDescriptor<TaskDefinition>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        let taskMap = Dictionary(tasks.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        let historicalData: [(date: String, entries: [(name: String, value: Double)])] = [
            ("2026-01-05", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Municipal Analytics", 4.25), ("Training", 0), ("Schach/Lesen", 0)]),
            ("2026-01-06", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Municipal Analytics", 6.25), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-07", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Municipal Analytics", 0), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-08", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 1), ("Putzen", 1), ("Municipal Analytics", 5.75), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-09", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Municipal Analytics", 0.75), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-12", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Municipal Analytics", 0), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-13", [("Nebenprojekt", 2), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Municipal Analytics", 0), ("Training", 0), ("Schach/Lesen", 2)]),
            ("2026-01-14", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Municipal Analytics", 0), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-15", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Municipal Analytics", 0.5), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-16", [("Nebenprojekt", 1), ("Aktuarwissenschaft", 0), ("Putzen", 2), ("Municipal Analytics", 1.5), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-19", [("Nebenprojekt", 2), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Municipal Analytics", 0), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-20", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Municipal Analytics", 0), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-21", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Municipal Analytics", 4.5), ("Training", 1), ("Schach/Lesen", 0)]),
            ("2026-01-22", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Municipal Analytics", 3.25), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-23", [("Nebenprojekt", 2), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Municipal Analytics", 4.0), ("Training", 0), ("Schach/Lesen", 1)]),
            // Catch-up: municipal analytics hours worked 1-15 Jul 2026 (matches server row seed-municipal-analytics-2026-07-10)
            ("2026-07-10", [("Municipal Analytics", 9.5)]),
        ]

        for day in historicalData {
            for entry in day.entries {
                guard let task = taskMap[entry.name] else { continue }
                let entryId = "seed-\(entry.name.lowercased().replacingOccurrences(of: " ", with: "-"))-\(day.date)"
                let dailyEntry = DailyEntry(
                    id: entryId,
                    task: task,
                    date: day.date,
                    value: entry.value
                )
                context.insert(dailyEntry)
            }
        }

        try? context.save()
    }
}
