import SwiftUI

/// Primary view: shows today's tasks and their progress.
struct DailyView: View {
    @State private var viewModel = DailyViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
                            .font(.headline)

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
                                },
                                onToggle: {
                                    viewModel.toggleCheckbox(for: progress.task.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("DailyTrack")
            .onAppear {
                viewModel.loadData()
            }
        }
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
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: min(score, 1.0))
                    .stroke(
                        scoreColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: score)

                VStack(spacing: 2) {
                    Text("\(Int(score * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if streak > 0 {
                Label("\(streak) \(String(localized: "day streak"))", systemImage: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }

    private var scoreColor: Color {
        switch score {
        case 0..<0.4: return .red
        case 0.4..<0.7: return .orange
        case 0.7..<0.9: return .yellow
        default: return .green
        }
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
                    .font(.headline)

                Spacer()

                // Completion percentage badge
                Text("\(Int(min(progress.dailyRatio, 1.0) * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeColor.opacity(0.15))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(badgeColor)
                        .frame(width: geo.size.width * min(progress.dailyRatio, 1.0), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress.dailyRatio)
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField("0", text: $inputText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .focused($isFocused)
                        .onSubmit { commitValue() }
                        .onChange(of: isFocused) { _, focused in
                            if !focused { commitValue() }
                        }

                    Text("/ \(formatNumber(progress.task.benchmark)) \(progress.task.unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Cumulative badge for cumulative tasks
                if let cumRatio = progress.cumulativeRatio {
                    VStack(alignment: .trailing) {
                        Text(String(localized: "Cumulative"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(cumRatio * 100))%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            inputText = progress.entry.value == 0 ? "" : formatNumber(progress.entry.value)
        }
    }

    private func commitValue() {
        let value = Double(inputText.replacingOccurrences(of: ",", with: ".")) ?? 0
        onValueChanged(value)
    }

    private var badgeColor: Color {
        switch progress.dailyRatio {
        case 0: return .gray
        case 0..<0.5: return .red
        case 0.5..<1.0: return .orange
        default: return .green
        }
    }

    private func formatNumber(_ n: Double) -> String {
        if n == n.rounded() { return String(Int(n)) }
        return String(format: "%.1f", n)
    }
}

#Preview {
    DailyView()
}
