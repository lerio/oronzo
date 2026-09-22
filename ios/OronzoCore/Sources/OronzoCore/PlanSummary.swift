import Foundation

/// What a plan amounts to before you start it: how long, how many blocks, how many exercises.
///
/// Two screens ask this — the plan summary and the row in the plan list — and they must not
/// answer it differently. Defining it once here is the same argument `DesignTokens.swift` makes
/// for the shared vocabulary and `PlanFlattener` makes for the shared execution order: one
/// definition makes drift impossible rather than merely discouraged.
///
/// **The time is part exact and part estimated, and the difference matters.**
///
/// Timed work and rests are known: they come off the flattened `[Interval]` stream rather than
/// being recomputed from the `Plan`, because deriving them from the plan alone would mean
/// re-implementing when `restAfter` and `restBetweenRounds` fire — the one contract that must
/// live in exactly three places and change together (`AGENTS.md`).
///
/// Rep-based work is *not* known. A rep-based step has no duration by definition, which is what
/// `mode: .reps` means, so it has to be estimated from a pace — see `secondsPerRep`. This is
/// the difference between an estimate and a floor: counting only the timed half of the Monday
/// plan gives 32.5 minutes for a workout the programme itself budgets at 45–50.
public struct PlanSummary: Equatable, Sendable {

    /// How long a rep-based set takes, per rep.
    ///
    /// **Calibrated against a real session**, which is the only honest basis for a constant
    /// like this. `supabase/plans/monday-upper-body-a.sql` — the plan whose own notes say
    /// "roughly 45–50 min" — sums to 1950s (32.5 min) of timed work and rest, and its 202
    /// uncounted reps take it to about 50 minutes in practice. At this pace the estimate lands
    /// on 45, the low end of the range the programme claims, which is the right place for it:
    /// an estimate read before a workout should be met without rushing.
    ///
    /// One session is one data point, so this is the right order of magnitude rather than a
    /// measurement, and it is worth revisiting with more of them. It beats what it replaced —
    /// a "timed work only" figure that was confidently half the truth.
    static let secondsPerRep: TimeInterval = 3.7

    let blockCount: Int
    let exerciseCount: Int

    /// Known exactly: every timed step, plus every rest the flattener emits.
    let timedSeconds: TimeInterval

    /// Estimated from the rep targets, at `secondsPerRep`.
    let repSeconds: TimeInterval

    /// What the workout will actually take.
    var estimatedSeconds: TimeInterval { timedSeconds + repSeconds }

    /// Part of the total is an estimate rather than a known duration, so it cannot be stated
    /// as a fact. True when any step is rep-based, or is timed but missing its duration —
    /// either way its contribution to the total is not something the plan can prove.
    let hasEstimatedWork: Bool

    public init(plan: Plan, intervals: [Interval]) {
        let steps: [PlanStep] = plan.blocks.flatMap { $0.steps }

        self.blockCount = plan.blocks.count
        self.exerciseCount = steps.count
        self.timedSeconds = intervals.compactMap(\.duration).reduce(0, +)
        self.repSeconds = steps
            .filter { $0.mode == .reps }
            .reduce(0) { total, step in
                total + Double(step.sets * (step.reps ?? 0)) * Self.secondsPerRep
            }
        self.hasEstimatedWork = steps.contains { $0.mode == .reps || $0.duration == nil }
    }

    /// The duration split into a count and a unit, so the written and the spoken forms cannot
    /// round differently.
    private var durationParts: (value: Int, isMinutes: Bool)? {
        guard estimatedSeconds > 0 else { return nil }

        // Round to nearest, but only once there is a minute to round to. Rounding first would
        // call a 35-second plan "1 min" — a near doubling, and short timed blocks are exactly
        // where a summary earns its place.
        return estimatedSeconds < 60
            ? (Int(estimatedSeconds.rounded()), false)
            : (Int((estimatedSeconds / 60).rounded()), true)
    }

    /// "45 min", "~45 min", or nil for a plan with nothing in it.
    ///
    /// The `~` is what `hasEstimatedWork` is for: a plan with rep-based work is not a duration
    /// the data can prove, and presenting it as one would be a promise the plan cannot keep.
    /// Spelling follows `MeasurementFormat`.
    var durationText: String? {
        guard let parts = durationParts else { return nil }

        let figure = parts.isMinutes ? "\(parts.value) min" : "\(parts.value)s"
        return hasEstimatedWork ? "~\(figure)" : figure
    }

    /// "~45 min · 5 blocks · 15 exercises", with any absent part left out.
    public var metaLine: String {
        var parts: [String] = []
        if let duration = durationText { parts.append(duration) }
        parts.append(count(blockCount, "block"))
        parts.append(count(exerciseCount, "exercise"))
        return parts.joined(separator: " · ")
    }

    /// The same line as it should be *heard*.
    ///
    /// VoiceOver reads `~` aloud as "tilde" and `min` as the abbreviation it is, so the meta
    /// line needs a spoken twin. It is composed here rather than in the view because no view in
    /// this project has a test target — a label assembled inside a `body` is a label nobody can
    /// assert on, which is how the session runner's controls once shipped announcing three
    /// anonymous buttons for a review to catch. `Interval.contextLabel` sets the precedent.
    public var spokenMetaLine: String {
        var parts: [String] = []
        if let duration = spokenDurationText { parts.append(duration) }
        parts.append(count(blockCount, "block"))
        parts.append(count(exerciseCount, "exercise"))
        return parts.joined(separator: ", ")
    }

    private var spokenDurationText: String? {
        guard let parts = durationParts else { return nil }

        let unit = parts.isMinutes
            ? (parts.value == 1 ? "minute" : "minutes")
            : (parts.value == 1 ? "second" : "seconds")
        let figure = "\(parts.value) \(unit)"
        return hasEstimatedWork ? "about \(figure)" : figure
    }

    private func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}
