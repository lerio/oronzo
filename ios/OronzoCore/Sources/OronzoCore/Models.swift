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
    public var mode: StepMode
    public var duration: TimeInterval?
    /// Base of the rep range — the number you start at. Nil for a timed step.
    public var reps: Int?
    /// Optional ceiling, making the target a range ("6-8"). Never below `reps`.
    public var repsMax: Int?
    public var targetWeightKg: Double?
    /// Optional ceiling, making the load a range ("50-60 kg").
    public var targetWeightMaxKg: Double?
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
        repsMax: Int? = nil,
        targetWeightKg: Double? = nil,
        targetWeightMaxKg: Double? = nil,
        restAfter: TimeInterval? = nil
    ) {
        self.exerciseID = exerciseID
        self.kind = kind
        self.label = label
        self.mode = mode
        self.duration = duration
        self.reps = reps
        self.repsMax = repsMax
        self.targetWeightKg = targetWeightKg
        self.targetWeightMaxKg = targetWeightMaxKg
        self.restAfter = restAfter
    }

    // MARK: - Display

    /// "6–8 reps", "10 reps", or nil for a timed step.
    public var repsDisplay: String? {
        kind == .rest ? nil : RangeFormat.reps(mode == .reps ? reps : nil, mode == .reps ? repsMax : nil)
    }

    /// "50–60 kg" or "20 kg".
    public var weightDisplay: String? {
        kind == .rest ? nil : RangeFormat.weight(targetWeightKg, targetWeightMaxKg)
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
    public let repsMax: Int?
    public let targetWeightKg: Double?
    public let targetWeightMaxKg: Double?
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
        repsMax: Int? = nil,
        targetWeightKg: Double?,
        targetWeightMaxKg: Double? = nil,
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
        self.repsMax = repsMax
        self.targetWeightKg = targetWeightKg
        self.targetWeightMaxKg = targetWeightMaxKg
        self.roundIndex = roundIndex
        self.blockIndex = blockIndex
        self.blockName = blockName
        self.exerciseID = exerciseID
    }

    // MARK: - Display

    /// "6–8 reps", "10 reps", or nil for a timed interval.
    public var repsDisplay: String? { RangeFormat.reps(reps, repsMax) }

    /// "50–60 kg" or "20 kg".
    public var weightDisplay: String? { RangeFormat.weight(targetWeightKg, targetWeightMaxKg) }

    /// The single value the Watch should lead with, if any — the base of the range.
    public var primaryTarget: String? {
        if let duration { return "\(Int(duration))s" }
        return repsDisplay
    }
}

/// Formats the "6–8" / "50–60 kg" shapes. One implementation, used by both `PlanStep` (the
/// prescription) and `Interval` (what actually runs), so the two cannot drift apart in how
/// they read.
public enum RangeFormat {

    /// Whole numbers lose their trailing ".0"; halves keep theirs.
    public static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    public static func reps(_ low: Int?, _ high: Int?) -> String? {
        guard let low else { return nil }
        if let high, high > low { return "\(low)–\(high) reps" }
        return "\(low) reps"
    }

    public static func weight(_ low: Double?, _ high: Double?) -> String? {
        guard let low else { return nil }
        if let high, high > low { return "\(number(low))–\(number(high)) kg" }
        return "\(number(low)) kg"
    }
}
