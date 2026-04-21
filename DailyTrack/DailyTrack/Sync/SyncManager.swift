import Foundation
import SwiftData

/// Manages bidirectional sync between local SwiftData and Cloudflare D1.
@Observable
final class SyncManager {
    var isSyncing = false
    var lastSyncDate: Date?
    var syncVersion: Int = 0
    var lastError: String?

    /// True once the first sync of this app session has completed (or if sync
    /// is disabled). The UI should avoid creating new DailyEntry objects until
    /// this is true, to prevent zero-value entries with fresh timestamps from
    /// overwriting real data on the server via last-write-wins.
    var hasCompletedInitialSync = false

    var apiURL: String {
        didSet { UserDefaults.standard.set(apiURL, forKey: "syncAPIURL") }
    }

    var syncToken: String {
        didSet { UserDefaults.standard.set(syncToken, forKey: "syncToken") }
    }

    var syncEnabled: Bool {
        !apiURL.isEmpty && !syncToken.isEmpty
    }

    private var autoSyncTask: Task<Void, Never>?
    private var debouncedSyncTask: Task<Void, Never>?

    private var lastSyncTimestamp: String {
        get { UserDefaults.standard.string(forKey: "lastSyncTimestamp") ?? "1970-01-01T00:00:00Z" }
        set { UserDefaults.standard.set(newValue, forKey: "lastSyncTimestamp") }
    }

    init() {
        self.apiURL = UserDefaults.standard.string(forKey: "syncAPIURL") ?? ""
        self.syncToken = UserDefaults.standard.string(forKey: "syncToken") ?? ""

        // If sync is disabled, the UI can create entries immediately —
        // there's no server data to conflict with.
        if !syncEnabled {
            hasCompletedInitialSync = true
        }
    }

    // MARK: - Auto Sync

    /// Debounced sync: waits 2 seconds after last call before syncing.
    /// Use this for on-change triggers to avoid hammering the API.
    func debouncedSync(context: ModelContext) {
        debouncedSyncTask?.cancel()
        debouncedSyncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await sync(context: context)
        }
    }

    func startAutoSync(context: ModelContext, interval: TimeInterval = 60) {
        autoSyncTask?.cancel()
        autoSyncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await sync(context: context)
            }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    // MARK: - Sync

    func sync(context: ModelContext) async {
        guard syncEnabled, !isSyncing else { return }

        await MainActor.run { isSyncing = true; lastError = nil }

        do {
            let isFirstSync = lastSyncTimestamp == "1970-01-01T00:00:00Z"

            if isFirstSync {
                // On first sync (fresh install / reinstall), ONLY pull.
                // The device has no meaningful local state — only seed data.
                // Pushing would send seed tasks/zero-value entries with fresh
                // timestamps that overwrite real data on the server.
                // Any seed tasks that duplicate server data will be reconciled
                // on the next normal sync cycle.
                try await pullChanges(context: context)
            } else if !hasCompletedInitialSync {
                // First sync of this app session (e.g. after Xcode reinstall
                // when the provisioning profile expired). Local DB has historical
                // data but the UI may have just created zero-value entries for
                // today with fresh timestamps. Pull first so server data wins,
                // then push any genuinely local changes, then reconcile.
                try await pullChanges(context: context)
                try await pushChanges(context: context)
                try await reconcile(context: context)
            } else {
                // Subsequent syncs within the same session: local data is
                // authoritative, so push first for efficiency.
                try await pushChanges(context: context)
                try await pullChanges(context: context)
                try await reconcile(context: context)
            }

            await MainActor.run {
                self.hasCompletedInitialSync = true
                self.lastSyncDate = Date()
                self.syncVersion += 1
                self.isSyncing = false
            }
        } catch {
            await MainActor.run {
                self.hasCompletedInitialSync = true
                self.lastError = error.localizedDescription
                self.isSyncing = false
            }
        }
    }

    // MARK: - Push

    private func pushChanges(context: ModelContext) async throws {
        let since = lastSyncTimestamp

        // Fetch locally modified tasks
        let recentTasks: [TaskDefinition] = try context.fetch(FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.updatedAt > since }
        ))

        // Always re-push all locally deleted tasks to ensure the server
        // knows about deletions, even if they were deleted before the last sync.
        let deletedTasks: [TaskDefinition] = try context.fetch(FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.deleted == true }
        ))

        // Merge both lists, deduplicating by ID
        var taskMap: [String: TaskDefinition] = [:]
        for task in recentTasks { taskMap[task.id] = task }
        for task in deletedTasks { taskMap[task.id] = task }
        let allTasks = Array(taskMap.values)

        // Fetch locally modified entries
        let allEntries: [DailyEntry] = try context.fetch(FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.updatedAt > since }
        ))

        guard !allTasks.isEmpty || !allEntries.isEmpty else { return }

        let payload: [String: Any] = [
            "tasks": allTasks.map { t -> [String: Any] in
                var dict: [String: Any] = [
                    "id": t.id, "name": t.name, "benchmark": t.benchmark,
                    "unit": t.unit, "weight": t.weight,
                    "is_cumulative": t.isCumulative, "cumulative_period": t.cumulativePeriod ?? "none",
                    "is_checkbox": t.isCheckbox,
                    "sort_order": t.sortOrder, "is_active": t.isActive,
                    "created_at": t.createdAt, "updated_at": t.updatedAt,
                    "deleted": t.deleted
                ]
                if let anchor = t.periodAnchor { dict["period_anchor"] = anchor }
                return dict
            },
            "entries": allEntries.map { e -> [String: Any] in
                var dict: [String: Any] = [
                    "id": e.id, "task_id": e.task?.id ?? "",
                    "date": e.date, "value": e.value,
                    "created_at": e.updatedAt, "updated_at": e.updatedAt,
                    "deleted": e.deleted
                ]
                if let notes = e.notes { dict["notes"] = notes }
                return dict
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: "\(apiURL)/sync")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.pushFailed
        }
    }

    // MARK: - Reconcile

    /// Tells the server which task IDs are active locally.
    /// The server marks any task NOT in this list as deleted,
    /// preventing stale tasks from being pulled back.
    private func reconcile(context: ModelContext) async throws {
        let activeTasks: [TaskDefinition] = try context.fetch(FetchDescriptor<TaskDefinition>(
            predicate: #Predicate { $0.deleted == false }
        ))

        let activeIds = activeTasks.map { $0.id }
        guard !activeIds.isEmpty else { return }

        let payload: [String: Any] = ["active_task_ids": activeIds]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: URL(string: "\(apiURL)/reconcile")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.reconcileFailed
        }
    }

    // MARK: - Pull

    private func pullChanges(context: ModelContext) async throws {
        let since = lastSyncTimestamp
        let isFirstSync = since == "1970-01-01T00:00:00Z"

        var request = URLRequest(url: URL(string: "\(apiURL)/sync?since=\(since)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.pullFailed
        }

        let syncResponse = try JSONDecoder().decode(SyncResponse.self, from: data)

        // Merge tasks
        for remoteTask in syncResponse.tasks {
            let taskId = remoteTask.id
            let existing: [TaskDefinition] = try context.fetch(FetchDescriptor<TaskDefinition>(
                predicate: #Predicate { $0.id == taskId }
            ))

            if let local = existing.first {
                // Deletion wins: never resurrect a locally deleted task
                if local.deleted && !remoteTask.deleted {
                    continue
                }

                // Remote deletion always wins regardless of timestamps
                if remoteTask.deleted && !local.deleted {
                    local.deleted = true
                    local.updatedAt = remoteTask.updatedAt
                    // Also soft-delete associated entries
                    if let entries = local.entries {
                        for entry in entries {
                            entry.deleted = true
                            entry.markUpdated()
                        }
                    }
                    continue
                }

                // On first sync, server data always wins over local data.
                // Local data is just seed data with artificially fresh timestamps —
                // the server has the real, user-edited state.
                let serverWins = isFirstSync || remoteTask.updatedAt > local.updatedAt

                if serverWins {
                    local.name = remoteTask.name
                    local.benchmark = remoteTask.benchmark
                    local.unit = remoteTask.unit
                    local.weight = remoteTask.weight
                    local.isCumulative = remoteTask.isCumulative
                    // Only overwrite cumulativePeriod if the server actually
                    // returned a value. A nil here means the server predates
                    // the cumulative-period feature and we should preserve
                    // whatever the local device has.
                    if let remotePeriod = remoteTask.cumulativePeriod {
                        local.cumulativePeriod = remotePeriod
                    }
                    // Same defensive pattern for periodAnchor.
                    if let remoteAnchor = remoteTask.periodAnchor {
                        local.periodAnchor = remoteAnchor
                    }
                    local.isCheckbox = remoteTask.isCheckbox
                    local.sortOrder = remoteTask.sortOrder
                    local.isActive = remoteTask.isActive
                    local.updatedAt = remoteTask.updatedAt
                    local.deleted = remoteTask.deleted
                }
            } else {
                // Task doesn't exist locally.
                // Skip if already deleted on server — no need to insert.
                if remoteTask.deleted {
                    continue
                }

                // If we have synced before (not a fresh device), and this task
                // was created before our last sync, we should have received it
                // previously. The fact that we don't have it means it was
                // deleted locally. Don't re-insert stale tasks.
                let isFirstSync = since == "1970-01-01T00:00:00Z"
                if !isFirstSync && remoteTask.createdAt < since {
                    continue
                }

                let newTask = TaskDefinition(
                    id: remoteTask.id,
                    name: remoteTask.name,
                    benchmark: remoteTask.benchmark,
                    unit: remoteTask.unit,
                    weight: remoteTask.weight,
                    isCumulative: remoteTask.isCumulative,
                    cumulativePeriod: remoteTask.cumulativePeriod,
                    periodAnchor: remoteTask.periodAnchor,
                    isCheckbox: remoteTask.isCheckbox,
                    sortOrder: remoteTask.sortOrder,
                    isActive: remoteTask.isActive,
                    createdAt: remoteTask.createdAt,
                    updatedAt: remoteTask.updatedAt,
                    deleted: remoteTask.deleted
                )
                context.insert(newTask)
            }
        }

        // Merge entries
        for remoteEntry in syncResponse.entries {
            let entryId = remoteEntry.id
            let existing: [DailyEntry] = try context.fetch(FetchDescriptor<DailyEntry>(
                predicate: #Predicate { $0.id == entryId }
            ))

            if let local = existing.first {
                // Deletion wins: never resurrect a locally deleted entry
                if local.deleted && !remoteEntry.deleted {
                    continue
                }

                // Remote deletion always wins regardless of timestamps
                if remoteEntry.deleted && !local.deleted {
                    local.deleted = true
                    local.updatedAt = remoteEntry.updatedAt
                    continue
                }

                // On first sync, server always wins (local entries are just seed data)
                let serverWins = isFirstSync || remoteEntry.updatedAt > local.updatedAt

                if serverWins {
                    local.value = remoteEntry.value
                    local.notes = remoteEntry.notes
                    local.updatedAt = remoteEntry.updatedAt
                    local.deleted = remoteEntry.deleted

                    // Re-link task if needed
                    if local.task?.id != remoteEntry.taskId {
                        let taskId = remoteEntry.taskId
                        let tasks: [TaskDefinition] = (try? context.fetch(FetchDescriptor<TaskDefinition>(
                            predicate: #Predicate { $0.id == taskId }
                        ))) ?? []
                        local.task = tasks.first
                    }
                }
            } else {
                // Skip deleted entries — no need to insert
                if remoteEntry.deleted {
                    continue
                }

                // Skip stale entries (see task logic above)
                let isFirstSync = since == "1970-01-01T00:00:00Z"
                if !isFirstSync && remoteEntry.updatedAt < since {
                    continue
                }

                // Find the parent task
                let taskId = remoteEntry.taskId
                let tasks: [TaskDefinition] = (try? context.fetch(FetchDescriptor<TaskDefinition>(
                    predicate: #Predicate { $0.id == taskId }
                ))) ?? []

                let newEntry = DailyEntry(
                    id: remoteEntry.id,
                    task: tasks.first,
                    date: remoteEntry.date,
                    value: remoteEntry.value,
                    notes: remoteEntry.notes,
                    updatedAt: remoteEntry.updatedAt,
                    deleted: remoteEntry.deleted
                )
                context.insert(newEntry)
            }
        }

        try context.save()
        lastSyncTimestamp = syncResponse.serverTime
    }

    enum SyncError: LocalizedError {
        case pushFailed, pullFailed, reconcileFailed

        var errorDescription: String? {
            switch self {
            case .pushFailed: return "Failed to push changes to server"
            case .pullFailed: return "Failed to pull changes from server"
            case .reconcileFailed: return "Failed to reconcile with server"
            }
        }
    }
}

// MARK: - Sync Response Model

private struct SyncResponse: Codable {
    let tasks: [CodableTaskDefinition]
    let entries: [CodableDailyEntry]
    let serverTime: String

    enum CodingKeys: String, CodingKey {
        case tasks, entries
        case serverTime = "server_time"
    }
}
