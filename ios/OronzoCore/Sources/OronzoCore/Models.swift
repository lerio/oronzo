import Foundation

public enum StepKind: String, Codable, Sendable {
    case exercise
    case rest
}

public enum StepMode: String, Codable, Sendable {
    /// Auto-advancing: the interval has a fixed duration and moves on by itself.
    case time
    /// Open-ended: waits for the user to tap when the set is done.
    case reps
}

/// How hard a timed step is meant to be — the effort, where `duration` is the extent.
///
/// Three words, and three only: `plan_steps.intensity` carries a check constraint on the same
/// three, so a fourth cannot exist in the database and every surface can switch on this
/// exhaustively rather than guessing at a string. Optional everywhere: a strength hold is just a
/// hold, and the builder only offers it for a timed step.
public enum Intensity: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case hard
}

/// A step is an **exercise**, always. Rest is not a kind of step: it comes from
/// `restAfter` below, or from a block's `restBetweenRounds`. (`StepKind` still exists and is
/// used by `Interval` — the execution stream really does contain rests, emitted between
/// sets. It is the *plan* that no longer pretends they are steps.)
public struct PlanStep: Codable, Equatable, Sendable {
    public var exerciseID: UUID?
    public var label: String?
    /// How many times this exercise repeats — its set count. (A *block's* `rounds` repeats
    /// a whole group; the two are deliberately different words.)
    public var sets: Int
    public var mode: StepMode
    public var duration: TimeInterval?
    /// The rep target. Nil for a timed step.
    public var reps: Int?
    public var targetWeightKg: Double?
    /// Rest after EACH set of this step, including the final one, so an exercise's rest
    /// carries you into the next exercise. See `PlanFlattener`.
    public var restAfter: TimeInterval?
    /// How hard this step is meant to be, for a timed one. Nil means nobody said.
    public var intensity: Intensity?

    public init(
        exerciseID: UUID? = nil,
        label: String? = nil,
        sets: Int = 1,
        mode: StepMode = .reps,
        duration: TimeInterval? = nil,
        reps: Int? = nil,
        targetWeightKg: Double? = nil,
        restAfter: TimeInterval? = nil,
        intensity: Intensity? = nil
    ) {
        self.exerciseID = exerciseID
        self.label = label
        self.sets = max(1, sets)
        self.mode = mode
        self.duration = duration
        self.reps = reps
        self.targetWeightKg = targetWeightKg
        self.restAfter = restAfter
        self.intensity = intensity
    }

    // MARK: - Display

    /// "10 reps", or nil for a timed step.
    public var repsDisplay: String? {
        mode == .time ? nil : MeasurementFormat.reps(reps)
    }

    /// "20 kg", or nil when no load is prescribed.
    public var weightDisplay: String? {
        MeasurementFormat.weight(targetWeightKg)
    }
}

public struct PlanBlock: Codable, Equatable, Sendable {
    public var name: String?
    public var rounds: Int
    /// Rest between rounds only — *not* after the final round.
    public var restBetweenRounds: TimeInterval?
    public var steps: [PlanStep]

    public init(name: String? = nil, rounds: Int = 1, restBetweenRounds: TimeInterval? = nil, steps: [PlanStep] = []) {
        self.name = name
        self.rounds = rounds
        self.restBetweenRounds = restBetweenRounds
        self.steps = steps
    }
}

public struct Plan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var blocks: [PlanBlock]

    public init(id: UUID = UUID(), name: String, blocks: [PlanBlock] = []) {
        self.id = id
        self.name = name
        self.blocks = blocks
    }
}

/// What the flattener and the plan summary need to know about an exercise.
///
/// Deliberately not the whole exercise. The `exercises` table also carries a default mode, rep
/// target and duration, and none of those survive into a plan — `PlanStep` snapshots what it
/// needs when the exercise is picked, which is why changing an exercise's defaults does not
/// rewrite the plans already using it. These two are the exception: they are read *while
/// flattening*, so they have to be handed in rather than frozen into the step.
public struct ExerciseInfo: Codable, Equatable, Sendable {
    public let name: String
    /// Performed once per side — left, then right. See `PlanFlattener.sideSuffixes`.
    public let hasTwoSides: Bool

    public init(name: String, hasTwoSides: Bool = false) {
        self.name = name
        self.hasTwoSides = hasTwoSides
    }
}

/// One entry in the flattened execution sequence — the unit the engine runs and the Watch
/// displays.
public struct Interval: Codable, Equatable, Sendable, Identifiable {
    public let index: Int
    public let kind: StepKind
    /// What to show: the exercise name, or "Break".
    public let name: String
    public let mode: StepMode?
    /// Non-nil for timed intervals *and* rests; nil for rep-based intervals.
    public let duration: TimeInterval?
    public let reps: Int?
    public let targetWeightKg: Double?
    /// Which set of the exercise this is (1-based).
    public let setIndex: Int
    /// How many sets that exercise has — so the UI can say "set 2 of 4" rather than "set 2",
    /// which is the difference between knowing and guessing how much is left.
    public let setCount: Int
    /// Which round of the enclosing block this is (1-based).
    public let blockRound: Int
    /// How many rounds that block has.
    public let blockRoundCount: Int
    public let blockName: String?
    public let exerciseID: UUID?
    /// How hard to go, for a timed interval whose step said so. Nil for everything else.
    ///
    /// **Optional, and that is the rule for this type.** `Interval` is `Codable` and travels to
    /// the watch whole, so a property has to decode from a snapshot written before it existed:
    /// the synthesised decoder does that only for an optional (`decodeIfPresent`). A nil one is
    /// also *omitted* from the JSON, so a workout with no intensity encodes byte-for-byte what it
    /// did before this field existed. A non-optional field with a default would not: the default
    /// never runs and the snapshot fails to decode, which is a silent "No workout" on the wrist.
    public let intensity: Intensity?

    public var id: Int { index }

    /// A timed interval advances on its own; a rep interval waits for the user.
    public var advancesAutomatically: Bool { duration != nil }

    public init(
        index: Int,
        kind: StepKind,
        name: String,
        mode: StepMode?,
        duration: TimeInterval?,
        reps: Int?,
        targetWeightKg: Double?,
        setIndex: Int,
        setCount: Int,
        blockRound: Int,
        blockRoundCount: Int,
        blockName: String?,
        exerciseID: UUID?,
        // The one defaulted parameter: twelve fixtures hand-build intervals to test the engine and
        // the watch projection, and none of them is about effort. `PlanFlattener` is the only
        // production call site, and `PlanFlattenerTests` pins that it passes this through.
        intensity: Intensity? = nil
    ) {
        self.index = index
        self.kind = kind
        self.name = name
        self.mode = mode
        self.duration = duration
        self.reps = reps
        self.targetWeightKg = targetWeightKg
        self.setIndex = setIndex
        self.setCount = setCount
        self.blockRound = blockRound
        self.blockRoundCount = blockRoundCount
        self.blockName = blockName
        self.exerciseID = exerciseID
        self.intensity = intensity
    }

    // MARK: - Display

    /// "10 reps", or nil for a timed interval.
    public var repsDisplay: String? { MeasurementFormat.reps(reps) }

    /// "20 kg", or nil when nothing is prescribed.
    public var weightDisplay: String? { MeasurementFormat.weight(targetWeightKg) }

    /// The line above the exercise: how much of the block is left, how hard to go, or failing
    /// that the block's name. Nil when there is nothing to say.
    ///
    /// **Effort sits between the set count and the round count.** A set number is progress —
    /// "set 2 of 4" is how much is left of this exercise, and `docs/ui-design/0001-ui-polish.md`
    /// calls that precedence correct — so an intensity does not displace it. A round number is
    /// progress too, but mid-interval the effort is the thing you need: "HARD" beats "round 4
    /// of 6", and a HIIT block is exactly where both would apply.
    public var contextLabel: String? {
        if setCount > 1 {
            return "Set \(setIndex) of \(setCount)"
        }
        if let intensity {
            return intensity.rawValue
        }
        if blockRoundCount > 1 {
            return "Round \(blockRound) of \(blockRoundCount)"
        }
        return blockName
    }
}

/// One implementation, shared by `PlanStep` (the prescription) and `Interval` (what actually
/// runs), so the two cannot drift apart in how they read.
public enum MeasurementFormat {

    /// Whole numbers lose their trailing ".0"; halves keep theirs.
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// "1:05". Rounded **up**, so the clock only reaches 0:00 when the interval is really
    /// over — reading 0:00 while a second still remains looks like a stalled timer.
    public static func clock(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func reps(_ value: Int?) -> String? {
        value.map { "\($0) reps" }
    }

    public static func weight(_ value: Double?) -> String? {
        value.map { "\(number($0)) kg" }
    }
}
