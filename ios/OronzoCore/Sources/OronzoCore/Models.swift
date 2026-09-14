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

public struct Exercise: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct PlanStep: Codable, Equatable, Sendable {
    public var exerciseID: UUID?
    public var kind: StepKind
    public var label: String?
    /// How many times this exercise repeats — its set count.
    public var rounds: Int
    public var mode: StepMode
    public var duration: TimeInterval?
    /// The rep target. Nil for a timed step.
    public var reps: Int?
    public var targetWeightKg: Double?
    /// Rest after EACH round of this step, including the final one, so an exercise's rest
    /// carries you into the next exercise. See `PlanFlattener`.
    public var restAfter: TimeInterval?

    public init(
        exerciseID: UUID? = nil,
        kind: StepKind = .exercise,
        label: String? = nil,
        rounds: Int = 1,
        mode: StepMode = .reps,
        duration: TimeInterval? = nil,
        reps: Int? = nil,
        targetWeightKg: Double? = nil,
        restAfter: TimeInterval? = nil
    ) {
        self.exerciseID = exerciseID
        self.kind = kind
        self.label = label
        self.rounds = max(1, rounds)
        self.mode = mode
        self.duration = duration
        self.reps = reps
        self.targetWeightKg = targetWeightKg
        self.restAfter = restAfter
    }

    // MARK: - Display

    /// "10 reps", or nil for a timed or rest step.
    public var repsDisplay: String? {
        kind == .rest || mode == .time ? nil : MeasurementFormat.reps(reps)
    }

    /// "20 kg", or nil when no load is prescribed.
    public var weightDisplay: String? {
        kind == .rest ? nil : MeasurementFormat.weight(targetWeightKg)
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
    /// Which round of the step this is (1-based) — i.e. which set.
    public let roundIndex: Int
    /// Which round of the enclosing block this is (1-based).
    public let blockRound: Int
    public let blockIndex: Int
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
        roundIndex: Int,
        blockRound: Int,
        blockIndex: Int,
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
        self.roundIndex = roundIndex
        self.blockRound = blockRound
        self.blockIndex = blockIndex
        self.blockName = blockName
        self.exerciseID = exerciseID
    }

    // MARK: - Display

    /// "10 reps", or nil for a timed interval.
    public var repsDisplay: String? { MeasurementFormat.reps(reps) }

    /// "20 kg", or nil when nothing is prescribed.
    public var weightDisplay: String? { MeasurementFormat.weight(targetWeightKg) }

    /// The value the Watch should lead with, if any.
    public var primaryTarget: String? {
        if let duration { return "\(Int(duration))s" }
        return repsDisplay
    }
}

/// One implementation, shared by `PlanStep` (the prescription) and `Interval` (what actually
/// runs), so the two cannot drift apart in how they read.
public enum MeasurementFormat {

    /// Whole numbers lose their trailing ".0"; halves keep theirs.
    public static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    public static func reps(_ value: Int?) -> String? {
        value.map { "\($0) reps" }
    }

    public static func weight(_ value: Double?) -> String? {
        value.map { "\(number($0)) kg" }
    }
}
