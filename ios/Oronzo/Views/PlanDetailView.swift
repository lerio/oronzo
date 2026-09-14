import OronzoCore
import SwiftUI

struct PlanDetailView: View {
    @Environment(PlanStore.self) private var store

    @State private var isRunning = false

    let plan: Plan

    private var intervals: [Interval] { store.intervals(for: plan) }

    var body: some View {
        List {
            Section {
                Button {
                    isRunning = true
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(intervals.isEmpty)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if !plan.blocks.isEmpty {
                Section("Blocks") {
                    ForEach(Array(plan.blocks.enumerated()), id: \.offset) { index, block in
                        BlockView(block: block, index: index)
                    }
                }
            }

            // The same flattening the engine executes. Showing it here means a plan that
            // reads oddly in the editor is obvious *before* you are mid-workout.
            Section {
                ForEach(intervals) { interval in
                    IntervalRow(interval: interval)
                }
            } header: {
                Text("Runs as \(intervals.count) step\(intervals.count == 1 ? "" : "s")")
            } footer: {
                Text("Rounds are expanded, and rests are shown as their own steps.")
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isRunning) {
            SessionRunner(plan: plan, exerciseNames: store.exerciseNames)
        }
    }
}

private struct BlockView: View {
    let block: PlanBlock
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(block.name ?? "Block \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if block.rounds > 1 {
                    Text("×\(block.rounds)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: .capsule)
                }
            }

            ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                HStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(step.label ?? "—")
                        .font(.callout)
                    if step.sets > 1 {
                        Text("×\(step.sets)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: .capsule)
                    }
                    Spacer()
                    Text(target(step))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func target(_ step: PlanStep) -> String {
        var parts: [String] = []
        if let duration = step.duration, step.mode == .time {
            parts.append("\(Int(duration))s")
        }
        if let reps = step.repsDisplay { parts.append(reps) }
        if let weight = step.weightDisplay { parts.append("@ \(weight)") }
        if let rest = step.restAfter { parts.append("+\(Int(rest))s rest") }
        return parts.joined(separator: " ")
    }
}

private struct IntervalRow: View {
    let interval: Interval

    /// Only mentions the round dimensions that actually repeat, so a plain step stays clean.
    private var contextLabel: String? {
        var parts: [String] = []
        if interval.setIndex > 1 { parts.append("set \(interval.setIndex)") }
        if interval.blockRound > 1 { parts.append("block round \(interval.blockRound)") }
        if let name = interval.blockName { parts.append(name) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(interval.index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(interval.name)
                    .font(.callout)
                    .foregroundStyle(interval.kind == .rest ? .secondary : .primary)
                if let context = contextLabel {
                    Text(context)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let duration = interval.duration {
                Label("\(Int(duration))s", systemImage: interval.kind == .rest ? "pause" : "timer")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else if let reps = interval.repsDisplay {
                Text(reps)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
