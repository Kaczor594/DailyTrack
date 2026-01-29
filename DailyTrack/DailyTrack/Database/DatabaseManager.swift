import Foundation
import SQLite3

/// Manages all SQLite database operations for DailyTrack.
/// Stores task definitions, daily entries, and configuration.
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let dbPath: String

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("DailyTrack", isDirectory: true)

        try? fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)
        dbPath = dbDir.appendingPathComponent("dailytrack.db").path

        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database: \(String(cString: sqlite3_errmsg(db)))")
        }
        // Enable WAL mode for better concurrent read performance
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA foreign_keys=ON")
    }

    private func createTables() {
        // Task definitions
        execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                benchmark REAL NOT NULL DEFAULT 1.0,
                unit TEXT NOT NULL DEFAULT '',
                weight REAL NOT NULL DEFAULT 1.0,
                is_cumulative INTEGER NOT NULL DEFAULT 0,
                is_checkbox INTEGER NOT NULL DEFAULT 0,
                sort_order INTEGER NOT NULL DEFAULT 0,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
        """)

        // Daily entries (one per task per day)
        execute("""
            CREATE TABLE IF NOT EXISTS daily_entries (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                date TEXT NOT NULL,
                value REAL NOT NULL DEFAULT 0.0,
                notes TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                UNIQUE(task_id, date)
            )
        """)

        // Indexes
        execute("CREATE INDEX IF NOT EXISTS idx_entries_date ON daily_entries(date)")
        execute("CREATE INDEX IF NOT EXISTS idx_entries_task_date ON daily_entries(task_id, date)")

        // App configuration (key-value store)
        execute("""
            CREATE TABLE IF NOT EXISTS config (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
        """)
    }

    // MARK: - Task CRUD

    func fetchAllTasks(activeOnly: Bool = true) -> [TaskDefinition] {
        let sql = activeOnly
            ? "SELECT * FROM tasks WHERE is_active = 1 ORDER BY sort_order, name"
            : "SELECT * FROM tasks ORDER BY sort_order, name"

        var tasks: [TaskDefinition] = []
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                tasks.append(taskFromStatement(stmt!))
            }
        }
        sqlite3_finalize(stmt)
        return tasks
    }

    func insertTask(_ task: TaskDefinition) {
        let sql = """
            INSERT OR REPLACE INTO tasks (id, name, benchmark, unit, weight, is_cumulative, is_checkbox, sort_order, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (task.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (task.name as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 3, task.benchmark)
            sqlite3_bind_text(stmt, 4, (task.unit as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 5, task.weight)
            sqlite3_bind_int(stmt, 6, task.isCumulative ? 1 : 0)
            sqlite3_bind_int(stmt, 7, task.isCheckbox ? 1 : 0)
            sqlite3_bind_int(stmt, 8, Int32(task.sortOrder))
            sqlite3_bind_int(stmt, 9, task.isActive ? 1 : 0)
            sqlite3_bind_text(stmt, 10, (task.createdAt as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func deleteTask(id: String) {
        execute("DELETE FROM tasks WHERE id = '\(id)'")
    }

    // MARK: - Daily Entry CRUD

    func fetchEntries(for date: String) -> [DailyEntry] {
        let sql = "SELECT * FROM daily_entries WHERE date = ? ORDER BY created_at"
        var entries: [DailyEntry] = []
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                entries.append(entryFromStatement(stmt!))
            }
        }
        sqlite3_finalize(stmt)
        return entries
    }

    func fetchEntries(forTask taskId: String) -> [DailyEntry] {
        let sql = "SELECT * FROM daily_entries WHERE task_id = ? ORDER BY date"
        var entries: [DailyEntry] = []
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (taskId as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                entries.append(entryFromStatement(stmt!))
            }
        }
        sqlite3_finalize(stmt)
        return entries
    }

    func upsertEntry(_ entry: DailyEntry) {
        let sql = """
            INSERT INTO daily_entries (id, task_id, date, value, notes, updated_at)
            VALUES (?, ?, ?, ?, ?, datetime('now'))
            ON CONFLICT(task_id, date) DO UPDATE SET
                value = excluded.value,
                notes = excluded.notes,
                updated_at = datetime('now')
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (entry.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (entry.taskId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (entry.date as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 4, entry.value)
            if let notes = entry.notes {
                sqlite3_bind_text(stmt, 5, (notes as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Analytics Queries

    /// Get cumulative total for a task across all dates
    func cumulativeTotal(forTask taskId: String) -> Double {
        let sql = "SELECT COALESCE(SUM(value), 0) FROM daily_entries WHERE task_id = ?"
        var stmt: OpaquePointer?
        var total: Double = 0

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (taskId as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                total = sqlite3_column_double(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        return total
    }

    /// Get daily completion scores for a date range
    func dailyScores(from startDate: String, to endDate: String) -> [(date: String, score: Double)] {
        let sql = """
            SELECT de.date,
                   SUM(
                       CASE WHEN t.is_checkbox = 1 THEN
                           CASE WHEN de.value > 0 THEN t.weight ELSE 0 END
                       ELSE
                           MIN(de.value / t.benchmark, 1.0) * t.weight
                       END
                   ) / NULLIF(SUM(t.weight), 0) as score
            FROM daily_entries de
            JOIN tasks t ON de.task_id = t.id
            WHERE de.date >= ? AND de.date <= ? AND t.is_active = 1 AND t.is_cumulative = 0
            GROUP BY de.date
            ORDER BY de.date
        """
        var results: [(String, Double)] = []
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (startDate as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (endDate as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let date = String(cString: sqlite3_column_text(stmt, 0))
                let score = sqlite3_column_double(stmt, 1)
                results.append((date, score))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    /// Get streak count (consecutive days with score >= threshold)
    func currentStreak(threshold: Double = 0.7) -> Int {
        let sql = """
            WITH daily AS (
                SELECT de.date,
                       SUM(
                           CASE WHEN t.is_checkbox = 1 THEN
                               CASE WHEN de.value > 0 THEN t.weight ELSE 0 END
                           ELSE
                               MIN(de.value / t.benchmark, 1.0) * t.weight
                           END
                       ) / NULLIF(SUM(t.weight), 0) as score
                FROM daily_entries de
                JOIN tasks t ON de.task_id = t.id
                WHERE t.is_active = 1 AND t.is_cumulative = 0
                GROUP BY de.date
                ORDER BY de.date DESC
            )
            SELECT date, score FROM daily
        """
        var streak = 0
        var stmt: OpaquePointer?
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            var expectedDate = Calendar.current.startOfDay(for: Date())
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dateStr = String(cString: sqlite3_column_text(stmt, 0))
                let score = sqlite3_column_double(stmt, 1)

                guard let rowDate = dateFormatter.date(from: dateStr) else { break }
                let rowDay = Calendar.current.startOfDay(for: rowDate)

                if rowDay == expectedDate && score >= threshold {
                    streak += 1
                    expectedDate = Calendar.current.date(byAdding: .day, value: -1, to: expectedDate)!
                } else {
                    break
                }
            }
        }
        sqlite3_finalize(stmt)
        return streak
    }

    /// Get all dates that have entries
    func allEntryDates() -> [String] {
        let sql = "SELECT DISTINCT date FROM daily_entries ORDER BY date"
        var dates: [String] = []
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                dates.append(String(cString: sqlite3_column_text(stmt, 0)))
            }
        }
        sqlite3_finalize(stmt)
        return dates
    }

    // MARK: - Config

    func getConfig(_ key: String) -> String? {
        let sql = "SELECT value FROM config WHERE key = ?"
        var stmt: OpaquePointer?
        var value: String?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                value = String(cString: sqlite3_column_text(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return value
    }

    func setConfig(_ key: String, value: String) {
        let sql = "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - JSON Export/Import (config file support)

    func exportTasksAsJSON() -> Data? {
        let tasks = fetchAllTasks(activeOnly: false)
        return try? JSONEncoder().encode(tasks)
    }

    func importTasksFromJSON(_ data: Data) {
        guard let tasks = try? JSONDecoder().decode([TaskDefinition].self, from: data) else { return }
        for task in tasks {
            insertTask(task)
        }
    }

    // MARK: - Helpers

    private func execute(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let msg = errMsg {
                print("SQL error: \(String(cString: msg))")
                sqlite3_free(msg)
            }
        }
    }

    private func taskFromStatement(_ stmt: OpaquePointer) -> TaskDefinition {
        TaskDefinition(
            id: String(cString: sqlite3_column_text(stmt, 0)),
            name: String(cString: sqlite3_column_text(stmt, 1)),
            benchmark: sqlite3_column_double(stmt, 2),
            unit: String(cString: sqlite3_column_text(stmt, 3)),
            weight: sqlite3_column_double(stmt, 4),
            isCumulative: sqlite3_column_int(stmt, 5) == 1,
            isCheckbox: sqlite3_column_int(stmt, 6) == 1,
            sortOrder: Int(sqlite3_column_int(stmt, 7)),
            isActive: sqlite3_column_int(stmt, 8) == 1,
            createdAt: String(cString: sqlite3_column_text(stmt, 9))
        )
    }

    private func entryFromStatement(_ stmt: OpaquePointer) -> DailyEntry {
        let notesPtr = sqlite3_column_text(stmt, 4)
        return DailyEntry(
            id: String(cString: sqlite3_column_text(stmt, 0)),
            taskId: String(cString: sqlite3_column_text(stmt, 1)),
            date: String(cString: sqlite3_column_text(stmt, 2)),
            value: sqlite3_column_double(stmt, 3),
            notes: notesPtr != nil ? String(cString: notesPtr!) : nil
        )
    }
}
