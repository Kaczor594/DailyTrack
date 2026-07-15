import SwiftUI
import SwiftData

/// Primary view: today's worksheet — score strip, task ledger, source line.
struct DailyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager
    @State private var viewModel = DailyViewModel()

    private var completedCount: Int {
        viewModel.taskProgressList.filter { $0.scoringRatio >= 1.0 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                    }

                    WorksheetHeader(
                        isoDate: viewModel.selectedDateString,
                        displayDate: viewModel.displayDate,
                        isToday: viewModel.isToday,
                        onPrevious: { viewModel.goToPreviousDay() },
                        onNext: { viewModel.goToNextDay() },
                        onToday: { viewModel.goToToday() }
                    )

                    ScoreStrip(
                        score: viewModel.dailyScore,
                        streak: viewModel.currentStreak,
                        completed: completedCount,
                        total: viewModel.taskProgressList.count
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(String(localized: "Tasks"))

                        TaskLedger(
                            items: viewModel.taskProgressList,
                            onValueChanged: { taskId, value in
                                viewModel.updateValue(for: taskId, value: value)
                                syncManager.debouncedSync(context: modelContext)
                            },
                            onToggle: { taskId in
                                viewModel.toggleCheckbox(for: taskId)
                                syncManager.debouncedSync(context: modelContext)
                            }
                        )
                    }

                    SourceLine(text: sourceText)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(PaperBackground())
            .refreshable {
                await syncManager.sync(context: modelContext)
                viewModel.loadData(context: modelContext)
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "Done")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
            #else
            .navigationTitle("DailyTrack")
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

    private var sourceText: String {
        var parts = ["\(viewModel.taskProgressList.count) \(String(localized: "Tasks"))"]
        if let lastSync = syncManager.lastSyncDate {
            let f = DateFormatter()
            f.timeStyle = .short
            parts.append("\(String(localized: "Last sync")) \(f.string(from: lastSync))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Worksheet Header

/// Page header: brand eyebrow + ISO date stamp, serif display date, date nav.
struct WorksheetHeader: View {
    let isoDate: String
    let displayDate: String
    let isToday: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onToday: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("DailyTrack · \(isoDate)")

            HStack(alignment: .center) {
                Text(displayDate)
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer()

                HStack(spacing: 6) {
                    if !isToday {
                        Button(action: onToday) {
                            Eyebrow(String(localized: "Today"), color: Theme.brand)
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusControl)
                                        .stroke(Theme.divider, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    DateNavButton(systemImage: "chevron.left", action: onPrevious)
                    DateNavButton(systemImage: "chevron.right", action: onNext)
                }
            }
        }
    }
}

struct DateNavButton: View {
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 28, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusControl)
                        .stroke(Theme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Score Strip

/// KPI strip: score, streak, completed count — hairline-divided, meter below.
struct ScoreStrip: View {
    let score: Double
    let streak: Int
    let completed: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                KPIBlock(
                    label: String(localized: "Score"),
                    value: "\(Int(score * 100))",
                    unit: "%",
                    valueColor: Theme.scoreColor(score)
                )

                Hairline(vertical: true).padding(.horizontal, 12)

                KPIBlock(
                    label: String(localized: "Streak"),
                    value: "\(streak)",
                    unit: String(localized: "days"),
                    valueColor: streak > 0 ? Theme.ink : Theme.inkTertiary
                )

                Hairline(vertical: true).padding(.horizontal, 12)

                KPIBlock(
                    label: String(localized: "Completed"),
                    value: "\(completed)",
                    unit: "/ \(total)",
                    valueColor: Theme.ink
                )

                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

            MeterBar(ratio: score)
        }
        .workbenchCard()
    }
}

struct KPIBlock: View {
    let label: String
    let value: String
    let unit: String
    var valueColor: Color = Theme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(label)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.monoMedium(24))
                    .foregroundStyle(valueColor)
                Text(unit)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}

// MARK: - Task Ledger

/// All tasks in one card, rows separated by hairlines — a worksheet, not
/// a stack of floating cards.
struct TaskLedger: View {
    let items: [TaskProgress]
    var onValueChanged: (String, Double) -> Void
    var onToggle: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, progress in
                TaskRowView(
                    progress: progress,
                    onValueChanged: { value in onValueChanged(progress.task.id, value) },
                    onToggle: { onToggle(progress.task.id) }
                )

                if index < items.count - 1 {
                    Hairline().padding(.leading, 14)
                }
            }
        }
        .workbenchCard(padded: false)
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
        HStack(alignment: .top, spacing: 10) {
            // Leading indicator: square check (toggles) or fill gauge
            if progress.task.isCheckbox {
                Button(action: onToggle) {
                    SquareCheckGlyph(isOn: progress.entry.value > 0)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-4)
                .padding(.top, 1)
            } else {
                SquareGauge(ratio: progress.scoringRatio)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progress.task.name)
                        .font(Theme.bodyMedium(15))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(min(progress.scoringRatio, 9.99) * 100))%")
                        .font(Theme.monoMedium(12))
                        .foregroundStyle(Theme.scoreColor(progress.scoringRatio))
                }

                if !progress.task.isCheckbox {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        UnderlineNumberField(
                            text: $inputText,
                            isFocused: $isFocused,
                            onCommit: commitValue
                        )

                        Text("/ \(formatNumber(dailyTarget)) \(progress.task.unit)")
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.inkSecondary)

                        Spacer()
                    }
                }

                // Period / cumulative context line
                if let periodText = progress.periodProgressText {
                    Eyebrow(periodText, size: 9, color: Theme.brand)
                } else if let cumRatio = progress.cumulativeRatio, !progress.task.hasPeriod {
                    Eyebrow("\(String(localized: "Cumulative")) · \(Int(cumRatio * 100))%", size: 9, color: Theme.info)
                }
            }
        }
        .padding(12)
        .padding(.leading, 2)
        .onAppear {
            inputText = progress.entry.value == 0 ? "" : formatNumber(progress.entry.value)
        }
        .onChange(of: progress.entry.value) { _, newValue in
            if !isFocused {
                inputText = newValue == 0 ? "" : formatNumber(newValue)
            }
        }
    }

    /// Daily target: derived per-day slice for period tasks, else benchmark.
    private var dailyTarget: Double {
        if progress.task.hasPeriod, let pd = progress.periodDays, pd > 0 {
            return progress.task.benchmark / Double(pd)
        }
        return progress.task.benchmark
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

/// Plain mono numeric field with a hairline underline — a form blank,
/// not a rounded input.
struct UnderlineNumberField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onCommit: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            TextField("0", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.monoMedium(14))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .focused(isFocused)
                .onSubmit { onCommit() }
                .onChange(of: isFocused.wrappedValue) { _, focused in
                    if !focused { onCommit() }
                }

            Rectangle()
                .fill(isFocused.wrappedValue ? Theme.brand : Theme.divider)
                .frame(height: 1)
        }
        .frame(width: 56)
    }
}

// MARK: - Sync Error Banner

/// Compact dismissible banner surfacing sync failures on the primary view.
struct SyncErrorBanner: View {
    let message: String
    var onRetry: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(String(localized: "Sync failed"), color: Theme.negative)
                Text(message)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onRetry) {
                Eyebrow(String(localized: "Retry"), color: Theme.ink)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .padding(.leading, 5)
        .background(Theme.terraSubtle)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.negative)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .stroke(Theme.divider, lineWidth: 1)
        )
    }
}

#Preview {
    DailyView()
        .modelContainer(for: [TaskDefinition.self, DailyEntry.self], inMemory: true)
}
