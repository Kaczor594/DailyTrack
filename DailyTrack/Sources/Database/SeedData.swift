import Foundation

/// Seeds initial task definitions from the Excel data on first launch.
struct SeedData {
    static func seedIfNeeded() {
        let db = DatabaseManager.shared
        let existingTasks = db.fetchAllTasks(activeOnly: false)

        // Only seed if database is empty
        guard existingTasks.isEmpty else { return }

        let initialTasks: [TaskDefinition] = [
            TaskDefinition(
                name: "Nebenprojekt",
                benchmark: 1.0,
                unit: NSLocalizedString("hour", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: false,
                sortOrder: 0
            ),
            TaskDefinition(
                name: "Aktuarwissenschaft",
                benchmark: 1.0,
                unit: NSLocalizedString("hour", comment: ""),
                weight: 1.0,
                isCumulative: true,
                isCheckbox: false,
                sortOrder: 1
            ),
            TaskDefinition(
                name: "Putzen",
                benchmark: 1.0,
                unit: NSLocalizedString("chore", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: true,
                sortOrder: 2
            ),
            TaskDefinition(
                name: "Bewerben",
                benchmark: 1.0,
                unit: NSLocalizedString("application", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: false,
                sortOrder: 3
            ),
            TaskDefinition(
                name: "Municipal Analytics",
                benchmark: 4.0,
                unit: NSLocalizedString("hours", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: false,
                sortOrder: 4
            ),
            TaskDefinition(
                name: "Training",
                benchmark: 1.0,
                unit: NSLocalizedString("workout", comment: ""),
                weight: 1.0,
                isCumulative: false,
                isCheckbox: true,
                sortOrder: 5
            ),
            TaskDefinition(
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
            db.insertTask(task)
        }

        // Seed historical data from Excel (Jan 5-23, 2026)
        seedHistoricalEntries()
    }

    private static func seedHistoricalEntries() {
        let db = DatabaseManager.shared
        let tasks = db.fetchAllTasks()
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.name, $0.id) })

        // Data from "Aufgaben Daten" sheet: [date: [taskName: value]]
        let historicalData: [(date: String, entries: [(name: String, value: Double)])] = [
            ("2026-01-05", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Bewerben", 0), ("Municipal Analytics", 4.25), ("Training", 0), ("Schach/Lesen", 0)]),
            ("2026-01-06", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Bewerben", 0), ("Municipal Analytics", 6.25), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-07", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Bewerben", 0), ("Municipal Analytics", 0), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-08", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 1), ("Putzen", 1), ("Bewerben", 0), ("Municipal Analytics", 5.75), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-09", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Bewerben", 2), ("Municipal Analytics", 0.75), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-12", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Bewerben", 0), ("Municipal Analytics", 0), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-13", [("Nebenprojekt", 2), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Bewerben", 1), ("Municipal Analytics", 0), ("Training", 0), ("Schach/Lesen", 2)]),
            ("2026-01-14", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Bewerben", 0), ("Municipal Analytics", 0), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-15", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Bewerben", 0), ("Municipal Analytics", 0.5), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-16", [("Nebenprojekt", 1), ("Aktuarwissenschaft", 0), ("Putzen", 2), ("Bewerben", 3), ("Municipal Analytics", 1.5), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-19", [("Nebenprojekt", 2), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Bewerben", 0), ("Municipal Analytics", 0), ("Training", 0), ("Schach/Lesen", 1)]),
            ("2026-01-20", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Bewerben", 0), ("Municipal Analytics", 0), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-21", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 1), ("Bewerben", 1), ("Municipal Analytics", 4.5), ("Training", 1), ("Schach/Lesen", 0)]),
            ("2026-01-22", [("Nebenprojekt", 0), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Bewerben", 0), ("Municipal Analytics", 3.25), ("Training", 1), ("Schach/Lesen", 1)]),
            ("2026-01-23", [("Nebenprojekt", 2), ("Aktuarwissenschaft", 0), ("Putzen", 0), ("Bewerben", 2), ("Municipal Analytics", 4.0), ("Training", 0), ("Schach/Lesen", 1)]),
        ]

        for day in historicalData {
            for entry in day.entries {
                guard let taskId = taskMap[entry.name] else { continue }
                let dailyEntry = DailyEntry(
                    taskId: taskId,
                    date: day.date,
                    value: entry.value
                )
                db.upsertEntry(dailyEntry)
            }
        }
    }
}
