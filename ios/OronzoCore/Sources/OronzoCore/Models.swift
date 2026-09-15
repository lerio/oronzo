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

    public init(
        exerciseID: UUID? = nil,
        label: String? = nil,
        sets: Int = 1,
        mode: StepMode = .reps,
        duration: TimeInterval? = nil,
        reps: Int? = nil,
        targetWeightKg: Double? = nil,
        restAfter: TimeInterval? = nil
    ) {
        self.exerciseID = exerciseID
        self.label = label
        self.sets = max(1, sets)
        self.mode = mode
        self.duration = duration
        self.reps = reps
        self.targetWeightKg = targetWeightKg
        self.restAfter = restAfter
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
        exerciseID: UUID?
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
    }

    // MARK: - Display

    /// "10 reps", or nil for a timed interval.
    public var repsDisplay: String? { MeasurementFormat.reps(reps) }

    /// "20 kg", or nil when nothing is prescribed.
    public var weightDisplay: String? { MeasurementFormat.weight(targetWeightKg) }

    /// The line above the exercise: how much of the block is left, or failing that the
    /// block's name. Nil when there is nothing to say.
    public var contextLabel: String? {
        if setCount > 1 {
            return "Set \(setIndex) of \(setCount)"
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
