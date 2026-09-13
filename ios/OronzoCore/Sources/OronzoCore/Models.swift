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

public struct PlanStep: Equatable, Sendable {
    public var exerciseID: UUID?
    public var kind: StepKind
    public var label: String?
    public var mode: StepMode
    public var duration: TimeInterval?
    public var reps: Int?
    public var targetWeightKg: Double?
    /// Rest inserted after this step *within* a round. Fires even on the last step of a
    /// round — see `PlanFlattener` for why.
    public var restAfter: TimeInterval?

    public init(
        exerciseID: UUID? = nil,
        kind: StepKind = .exercise,
        label: String? = nil,
        mode: StepMode = .reps,
        duration: TimeInterval? = nil,
        reps: Int? = nil,
        targetWeightKg: Double? = nil,
        restAfter: TimeInterval? = nil
    ) {
        self.exerciseID = exerciseID
        self.kind = kind
        self.label = label
        self.mode = mode
        self.duration = duration
        self.reps = reps
        self.targetWeightKg = targetWeightKg
        self.restAfter = restAfter
    }
}

public struct PlanBlock: Equatable, Sendable {
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

public struct Plan: Equatable, Sendable {
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
public struct Interval: Equatable, Sendable, Identifiable {
    public let index: Int
    public let kind: StepKind
    /// What to show: the exercise name, or "Break".
    public let name: String
    public let mode: StepMode?
    /// Non-nil for timed intervals *and* rests; nil for rep-based intervals.
    public let duration: TimeInterval?
    public let reps: Int?
    public let targetWeightKg: Double?
    public let roundIndex: Int
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
        self.blockIndex = blockIndex
        self.blockName = blockName
        self.exerciseID = exerciseID
    }
}
