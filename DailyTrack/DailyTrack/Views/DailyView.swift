import SwiftUI
import SwiftData

/// Primary view: shows today's tasks and their progress.
struct DailyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @State private var viewModel = DailyViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Sync failure banner
                    if let error = syncManager.lastError {
                        SyncErrorBanner(
                            message: error,
                            onRetry: {
                                Task { await syncManager.sync(context: modelContext) }
                            },
                            onDismiss: {
                                syncManager.lastError = nil
                            }
                        )
                        .padding(.horizontal)
                    }

                    // Daily score ring
                    DailyScoreCard(
                        score: viewModel.dailyScore,
                        streak: viewModel.currentStreak,
                        dateLabel: viewModel.displayDate
                    )

                    // Date navigation
                    HStack {
                        Button {
                            viewModel.goToPreviousDay()
                        } label: {
                            Image(systemName: "chevron.left")
                        }

                        Spacer()

                        Text(viewModel.displayDate)
                            .font(Theme.bodySemiBold(15))
                            .foregroundStyle(Theme.ink)

                        Spacer()

                        if !viewModel.isToday {
                            Button(String(localized: "Today")) {
                                viewModel.goToToday()
                            }
                            .font(.caption)
                        }

                        Button {
                            viewModel.goToNextDay()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .padding(.horizontal)

                    // Task list
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.taskProgressList) { progress in
                            TaskRowView(
                                progress: progress,
                                onValueChanged: { value in
                                    viewModel.updateValue(for: progress.task.id, value: value)
                                    syncManager.debouncedSync(context: modelContext)
                                },
                                onToggle: {
                                    viewModel.toggleCheckbox(for: progress.task.id)
                                    syncManager.debouncedSync(context: modelContext)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Theme.background)
            .refreshable {
                await syncManager.sync(context: modelContext)
                viewModel.loadData(context: modelContext)
            }
            .navigationTitle("DailyTrack")
            #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "Done")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
            #endif
            .onAppear {
                viewModel.loadData(context: modelContext, canCreateEntries: syncManager.hasCompletedInitialSync)
            }
            .onChange(of: syncManager.hasCompletedInitialSync) { _, completed in
                if completed {
                    viewModel.loadData(context: modelContext)
                }
            }
            .onChange(of: syncManager.syncVersion) { _, _ in
                viewModel.loadData(context: modelContext)
            }
        }
    }
}

// MARK: - Sync Error Banner

/// Compact dismissible banner surfacing sync failures on the primary view.
struct SyncErrorBanner: View {
    let message: String
    var onRetry: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.negative)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Sync failed"))
                    .font(Theme.bodySemiBold(12))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(String(localized: "Retry")) {
                onRetry()
            }
            .font(Theme.bodyMedium(12))
            .buttonStyle(.bordered)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Theme.terraSubtle)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }
}

// MARK: - Daily Score Card

struct DailyScoreCard: View {
    let score: Double
    let streak: Int
    let dateLabel: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Theme.divider, lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: min(score, 1.0))
                    .stroke(
                        Theme.scoreColor(score),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: score)

                VStack(spacing: 2) {
                    Text("\(Int(score * 100))%")
                        .font(Theme.displaySemiBold(30))
                        .foregroundStyle(Theme.ink)
                    Text(dateLabel)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            if streak > 0 {
                Label("\(streak) \(String(localized: "day streak"))", systemImage: "flame.fill")
                    .font(Theme.bodyMedium(14))
                    .foregroundStyle(Theme.terra)
            }
        }
        .padding()
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    let progress: TaskProgress
    var onValueChanged: (Double) -> Void
    var onToggle: () -> Void

    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: task name + completion badge
            HStack {
                Text(progress.task.name)
                    .font(Theme.bodySemiBold(15))
                    .foregroundStyle(Theme.ink)

                Spacer()

                // Completion percentage badge
                Text("\(Int(progress.scoringRatio * 100))%")
                    .font(Theme.monoMedium(11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.scoreColor(progress.scoringRatio).opacity(0.15))
                    .foregroundStyle(Theme.scoreColor(progress.scoringRatio))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.radiusBar)
                        .fill(Theme.panel)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: Theme.radiusBar)
                        .fill(Theme.scoreColor(progress.scoringRatio))
                        .frame(width: geo.size.width * min(progress.scoringRatio, 1.0), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress.scoringRatio)
                }
            }
            .frame(height: 6)

            // Input area
            HStack {
                if progress.task.isCheckbox {
                    Toggle(isOn: Binding(
                        get: { progress.entry.value > 0 },
                        set: { _ in onToggle() }
                    )) {
                        Text(progress.task.unit.isEmpty ? String(localized: "Complete") : progress.task.unit)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    TextField("0", text: $inputText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .focused($isFocused)
                        .onSubmit { commitValue() }
                        .onChange(of: isFocused) { _, focused in
                            if !focused { commitValue() }
                        }

                    if progress.task.hasPeriod, let pd = progress.periodDays, pd > 0 {
                        let dailyTarget = progress.task.benchmark / Double(pd)
                        Text("/ \(formatNumber(dailyTarget)) \(progress.task.unit)")
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.inkSecondary)
                    } else {
                        Text("/ \(formatNumber(progress.task.benchmark)) \(progress.task.unit)")
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                Spacer()

                // Period progress badge for period-cumulative tasks
                if let periodText = progress.periodProgressText {
                    VStack(alignment: .trailing) {
                        Text(periodText)
                            .font(Theme.monoMedium(11))
                            .foregroundStyle(Theme.brand)
                    }
                }
                // Lifetime cumulative badge for non-period cumulative tasks
                else if let cumRatio = progress.cumulativeRatio, !progress.task.hasPeriod {
                    VStack(alignment: .trailing) {
                        Text(String(localized: "Cumulative"))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.inkSecondary)
                        Text("\(Int(cumRatio * 100))%")
                            .font(Theme.monoMedium(11))
                            .foregroundStyle(Theme.info)
                    }
                }
            }
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.divider, lineWidth: 1)
        )
        .onAppear {
            inputText = progress.entry.value == 0 ? "" : formatNumber(progress.entry.value)
        }
        .onChange(of: progress.entry.value) { _, newValue in
            if !isFocused {
                inputText = newValue == 0 ? "" : formatNumber(newValue)
            }
        }
    }

    private func commitValue() {
        let value = Double(inputText.replacingOccurrences(of: ",", with: ".")) ?? 0
        onValueChanged(value)
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() { return String(Int(n)) }
        return String(format: "%.1f", n)
    }
}

#Preview {
    DailyView()
        .modelContainer(for: [TaskDefinition.self, DailyEntry.self], inMemory: true)
}
