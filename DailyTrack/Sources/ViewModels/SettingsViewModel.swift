import Foundation
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// View model for the task configuration / settings screen.
@Observable
final class SettingsViewModel {
    var tasks: [TaskDefinition] = []
    var editingTask: TaskDefinition?
    var showingAddSheet = false
    var showingEditSheet = false

    private let db = DatabaseManager.shared

    func loadTasks() {
        tasks = db.fetchAllTasks(activeOnly: false)
    }

    func addTask(_ task: TaskDefinition) {
        var newTask = task
        newTask.sortOrder = tasks.count
        db.insertTask(newTask)
        loadTasks()
    }

    func updateTask(_ task: TaskDefinition) {
        db.insertTask(task)
        loadTasks()
    }

    func deleteTask(_ task: TaskDefinition) {
        db.deleteTask(id: task.id)
        loadTasks()
    }

    func moveTask(from source: IndexSet, to destination: Int) {
        tasks.move(fromOffsets: source, toOffset: destination)
        for (index, task) in tasks.enumerated() {
            var updated = task
            updated.sortOrder = index
            db.insertTask(updated)
        }
    }

    func toggleActive(_ task: TaskDefinition) {
        var updated = task
        updated.isActive.toggle()
        db.insertTask(updated)
        loadTasks()
    }

    // MARK: - JSON Export/Import

    func exportJSON() -> Data? {
        db.exportTasksAsJSON()
    }

    func importJSON(_ data: Data) {
        db.importTasksFromJSON(data)
        loadTasks()
    }

    func configFilePath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DailyTrack/tasks_config.json")
    }

    func saveConfigFile() {
        guard let data = exportJSON() else { return }
        try? data.write(to: configFilePath())
    }

    func loadConfigFile() {
        let path = configFilePath()
        guard let data = try? Data(contentsOf: path) else { return }
        importJSON(data)
    }
}
