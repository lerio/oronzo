import OronzoCore
import SwiftUI

struct PlanDetailView: View {
    @Environment(PlanStore.self) private var store

    let plan: Plan

    private var intervals: [Interval] { store.intervals(for: plan) }

    var body: some View {
        List {
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
                    Image(systemName: step.kind == .rest ? "pause" : "figure.strengthtraining.traditional")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(step.label ?? "—")
                        .font(.callout)
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
        if step.kind == .rest {
            if let duration = step.duration { parts.append("\(Int(duration))s") }
        } else if step.mode == .time, let duration = step.duration {
            parts.append("\(Int(duration))s")
        } else if let reps = step.reps {
            parts.append("\(reps) reps")
        }
        if let weight = step.targetWeightKg { parts.append("@ \(formatted(weight))kg") }
        if let rest = step.restAfter { parts.append("+\(Int(rest))s rest") }
        return parts.joined(separator: " ")
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct IntervalRow: View {
    let interval: Interval

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
                if interval.roundIndex > 1 || interval.blockName != nil {
                    Text("round \(interval.roundIndex)\(interval.blockName.map { " · \($0)" } ?? "")")
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
            } else if let reps = interval.reps {
                Text("\(reps) reps")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
