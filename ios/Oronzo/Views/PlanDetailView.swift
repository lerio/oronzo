import OronzoCore
import SwiftUI

/// The plan summary: what you are about to do, read before you start it.
///
/// One of the "seconds-long screens" `docs/spec/0001-ui-polish.md` deferred, so it **inherits**
/// the vocabulary in `DesignTokens.swift` rather than adding to it — four type roles, four
/// spacing steps, and nothing essential drawn in `muted`. There is no `primary` role here: that
/// figure is sized for reading at 1–2 metres during a session, and this page is read at arm's
/// length. The largest thing on this screen is the plan's name, at `title`.
///
/// It lists the plan **as authored** — blocks, then the exercises in each — not as flattened.
/// The flattened list it replaced expanded every set and every round, so a six-round block
/// became twelve near-identical rows and the shape of the plan disappeared. What the summary
/// owes you is "what am I doing", and the shape answers that better than the execution order.
///
/// Steps are named through `PlanFlattener.name(for:exercises:)` rather than `step.label`
/// directly, so this screen and the workout that follows it cannot name the same exercise
/// differently. Both matter: `label` is null on every step the builder writes
/// (`docs/known-issues.md` §1), so the exercise table is the branch that actually runs.
struct PlanDetailView: View {
    @Environment(PlanStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Environment(SessionHost.self) private var session

    /// Measured, not guessed: the button's height grows with Dynamic Type, and the content has
    /// to clear whatever it turns out to be.
    @State private var startBarHeight: CGFloat = 0

    let plan: Plan

    // Text scales with Dynamic Type, exactly as `SessionRunner` binds it — see the note in
    // `DesignTokens.swift` on why only the distance-read figure is exempt.
    @ScaledMetric(relativeTo: .title2) private var titleSize = TypeScale.size(.title, on: .phone)
    @ScaledMetric(relativeTo: .body) private var labelSize = TypeScale.size(.label, on: .phone)
    @ScaledMetric(relativeTo: .caption) private var captionSize = TypeScale.size(.caption, on: .phone)

    /// A corner radius is an implementation decision (`docs/ui-design/0001-ui-polish.md` §9),
    /// but it does not need a number of its own — borrowing the spacing scale keeps it out of
    /// the one-off budget.
    private var cardRadius: CGFloat { SpacingStep.roomy.points }

    private var intervals: [Interval] { store.intervals(for: plan) }
    private var summary: PlanSummary { PlanSummary(plan: plan, intervals: intervals, exercises: store.exercises) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingStep.roomy.points) {
                header

                if plan.blocks.isEmpty {
                    empty
                } else {
                    // Neither `PlanBlock` nor `PlanStep` is `Identifiable`, and two steps in a
                    // block can be equal values — the same offset identity the old screen used.
                    // Safe here because this view holds an immutable snapshot of `plan`.
                    ForEach(Array(plan.blocks.enumerated()), id: \.offset) { index, block in
                        blockSection(block, index: index)
                    }
                }
            }
            .padding(.horizontal, SpacingStep.edge.points)
            .padding(.top, SpacingStep.snug.points)
            // Room for the floating button, so the last exercise can always be scrolled clear
            // of it rather than sitting permanently underneath.
            .padding(.bottom, startBarHeight + SpacingStep.roomy.points)
        }
        .background(ColorRole.background.color(colorScheme).ignoresSafeArea())
        // An overlay, not a `safeAreaInset`: the button floats *over* the list, with the plan
        // scrolling underneath it, rather than docked in a bar of its own.
        .overlay(alignment: .bottom) {
            startBar
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { startBarHeight = $0 }
        }
        // The title is the first thing in the content rather than a bar title that scrolls
        // away: with no `navigationTitle`, the back button still reads "Plans".
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: SpacingStep.tight.points) {
            // Same size, weight and design as `title` in the session runner, so the role reads
            // the same on both surfaces — that is the whole point of a shared scale.
            Text(plan.name)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorRole.text.color(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(summary.metaLine)
                .font(.system(size: captionSize))
                .foregroundStyle(ColorRole.text.color(colorScheme))
                // "~26 min" is read aloud as "tilde twenty-six min"; this says it properly.
                .accessibilityLabel(summary.spokenMetaLine)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: SpacingStep.tight.points) {
            Text("This plan has no blocks yet.")
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(ColorRole.text.color(colorScheme))
            Text("Build one in the web app, then pull to refresh the plan list.")
                .font(.system(size: captionSize))
                .foregroundStyle(ColorRole.text.color(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Blocks

    private func blockSection(_ block: PlanBlock, index: Int) -> some View {
        VStack(alignment: .leading, spacing: SpacingStep.snug.points) {
            blockHeader(block, index: index)

            if block.steps.isEmpty {
                Text("No exercises in this block.")
                    .font(.system(size: captionSize))
                    .foregroundStyle(ColorRole.text.color(colorScheme))
                    .padding(SpacingStep.snug.points)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ColorRole.surface.color(colorScheme), in: .rect(cornerRadius: cardRadius))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(block.steps.enumerated()), id: \.offset) { stepIndex, step in
                        if stepIndex > 0 { Divider() }
                        stepRow(step)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ColorRole.surface.color(colorScheme), in: .rect(cornerRadius: cardRadius))
            }
        }
    }

    /// Stacked at accessibility sizes for the same reason the rows are: a wrapped block name
    /// with its badge stranded at the end of the first line reads as an accident.
    @ViewBuilder
    private func blockHeader(_ block: PlanBlock, index: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SpacingStep.tight.points) {
                blockName(block, index: index)
                if block.rounds > 1 { roundsBadge(block.rounds) }
            }
        } else {
            HStack(spacing: SpacingStep.snug.points) {
                blockName(block, index: index)
                if block.rounds > 1 { roundsBadge(block.rounds) }
            }
        }
    }

    private func blockName(_ block: PlanBlock, index: Int) -> some View {
        Text(block.name ?? "Block \(index + 1)")
            .font(.system(size: labelSize, weight: .semibold))
            .foregroundStyle(ColorRole.text.color(colorScheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// Reinforces the block's repetition. The shipped capsule from `SessionRunner` and the Lock
    /// Screen widget, so the three surfaces draw a badge the same way.
    private func roundsBadge(_ rounds: Int) -> some View {
        Text("×\(rounds)")
            .font(.system(size: captionSize, weight: .semibold))
            .foregroundStyle(ColorRole.text.color(colorScheme))
            .padding(.horizontal, SpacingStep.snug.points)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(ColorRole.accent.color(colorScheme), lineWidth: 2))
            .accessibilityLabel("\(rounds) rounds")
    }

    /// One exercise. The name carries the row and the prescription trails it — subordinate by
    /// **size**, never by dimming: `muted` is reserved for chrome that can be lost, and reps are
    /// not chrome.
    @ViewBuilder
    private func stepRow(_ step: PlanStep) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Stacked, not three columns. At these sizes the name and the prescription
                // cannot share the width: the name wraps to four lines beside a stranded "×4",
                // which is harder to read than the two lines this costs.
                VStack(alignment: .leading, spacing: SpacingStep.tight.points) {
                    stepName(step)
                    HStack(spacing: SpacingStep.snug.points) {
                        setsMarker(step)
                        stepTarget(step)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: SpacingStep.snug.points) {
                    stepName(step)
                    setsMarker(step)
                    Spacer(minLength: SpacingStep.snug.points)
                    stepTarget(step)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // `snug`, not `roomy`: the card already sits at the page margin, so a wider inner
        // inset pushed the exercises to twice the block title's indent.
        .padding(.horizontal, SpacingStep.snug.points)
        .padding(.vertical, SpacingStep.snug.points)
        .accessibilityElement(children: .combine)
    }

    /// The exercise name is one step down from the block title, so the block still heads its
    /// own section. `caption` is the next role down — the vocabulary has no in-between size on
    /// purpose, so "a bit smaller" means this step and not a new number.
    private func stepName(_ step: PlanStep) -> some View {
        Text(PlanFlattener.name(for: step, exercises: store.exercises))
            .font(.system(size: captionSize))
            .foregroundStyle(ColorRole.text.color(colorScheme))
            // At the largest Dynamic Type sizes the name takes the full width rather than
            // truncating — an exercise name is not something to abbreviate.
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func setsMarker(_ step: PlanStep) -> some View {
        if step.sets > 1 {
            // "×3 each side" rather than "×3" when the exercise is done per side, because this
            // screen is read *before* the workout and the workout runs six intervals, not three.
            // The name above stays side-free — the plan is listed as authored — but the
            // prescription has to describe what will actually happen.
            let perSide = PlanFlattener.sideSuffixes(of: step, exercises: store.exercises).count > 1
            Text(perSide ? "×\(step.sets) each side" : "×\(step.sets)")
                .font(.system(size: captionSize).monospacedDigit())
                .foregroundStyle(ColorRole.text.color(colorScheme))
                .accessibilityLabel(perSide ? "\(step.sets) sets, each side" : "\(step.sets) sets")
        }
    }

    @ViewBuilder
    private func stepTarget(_ step: PlanStep) -> some View {
        if let target = target(step) {
            Text(target)
                .font(.system(size: captionSize).monospacedDigit())
                .foregroundStyle(ColorRole.text.color(colorScheme))
        }
    }

    /// The prescription: how long, or how many.
    ///
    /// Durations go through `MeasurementFormat.clock`, which is the spelling the runner counts
    /// down in — "0:20" here and "0:20" mid-workout, rather than this screen saying "20s".
    ///
    /// The target weight is deliberately absent. It is shown in the runner, where you are
    /// standing at the rack and it is the number you need; on a summary read beforehand it only
    /// made the right-hand column longer.
    private func target(_ step: PlanStep) -> String? {
        var parts: [String] = []
        if step.mode == .time, let duration = step.duration {
            parts.append(MeasurementFormat.clock(remaining: duration))
        }
        if let reps = step.repsDisplay { parts.append(reps) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Start

    /// Anchored rather than scrolled to: starting is the one thing this screen is for, and it
    /// should not depend on having scrolled to the bottom of a long plan.
    ///
    /// No backing bar. The list passes behind the pill, which is opaque, so the button stays
    /// legible without a surface that would read as a card the list is not.
    private var startBar: some View {
        Button {
            // Hands the session to the host rather than to a cover of this screen's own. The
            // runner is presented at the root, so starting a workout no longer ties its lifetime
            // to this view — and nothing this view does can end one.
            session.begin(plan: plan, exercises: store.exercises)
        } label: {
            Text("Start")
                .font(.system(size: labelSize, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(ColorRole.accent.color(colorScheme))
        .disabled(intervals.isEmpty)
        .accessibilityHint("Starts the workout")
        .padding(.horizontal, SpacingStep.edge.points)
        .padding(.bottom, SpacingStep.snug.points)
    }
}

#if DEBUG
#Preview("Plan summary") {
    NavigationStack {
        // The builder-shaped plan, not `make()`: it carries null labels and names each step
        // from the exercise table, which is what a real plan looks like on this screen.
        PlanDetailView(plan: DemoPlan.builderShaped())
    }
    .environment(PlanStore.seeded(DemoPlan.builderExercises))
}
#endif
