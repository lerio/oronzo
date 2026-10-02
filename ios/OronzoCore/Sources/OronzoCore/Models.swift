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
///
/// **Declaration order is effort-ascending, and that is load-bearing.** `LoadDial.intensity` cycles
/// `allCases`, so the runner's arrows step low → medium → hard and the order of these three lines
/// decides what "harder" means. The database's check constraint only tests membership — it has no
/// notion that `hard > medium` — so this enum is the sole statement of the ordering, and
/// `LoadAdjustmentTests` pins it.
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
    /// The `plan_steps` row this step came from, when it came from the database.
    ///
    /// Optional because a step can be built in code — `DemoPlan`, and every test fixture — with no
    /// row behind it. It is the only identity that survives flattening far enough to write back to:
    /// `exerciseID` is not it, since one plan can prescribe the same exercise twice at different
    /// loads. See `Interval.stepID`.
    ///
    /// **Not stable across a save.** `save_plan` deletes and re-inserts the whole tree, so every
    /// step id is minted anew each time the web builder saves — which is why a session holds this
    /// only for as long as it is running, and why the write it makes checks that the row was
    /// actually there. See `PlanRepository.updateStepLoad`.
    public var id: UUID?
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
    /// A "Get in position" interval of this many seconds before each set — and before each side
    /// of a two-sided exercise. Nil means none, which is what an untimed step always has.
    ///
    /// **Opt-in, and it is the plan's decision rather than a rule of the flattener**, because a
    /// timed step is not always work: the seeded HIIT blocks prescribe their recoveries as timed
    /// steps too ("Easy — 40 sec"), and nothing in the model tells those apart from a hold.
    ///
    /// A duration rather than a flag so that a per-step value needs no second migration; the
    /// builder offers five seconds and nothing else. See `PlanFlattener`.
    public var prepareSeconds: TimeInterval?

    public init(
        id: UUID? = nil,
        exerciseID: UUID? = nil,
        label: String? = nil,
        sets: Int = 1,
        mode: StepMode = .reps,
        duration: TimeInterval? = nil,
        reps: Int? = nil,
        targetWeightKg: Double? = nil,
        restAfter: TimeInterval? = nil,
        intensity: Intensity? = nil,
        prepareSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.label = label
        self.sets = max(1, sets)
        self.mode = mode
        self.duration = duration
        self.reps = reps
        self.targetWeightKg = targetWeightKg
        self.restAfter = restAfter
        self.intensity = intensity
        self.prepareSeconds = prepareSeconds
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
    /// The `plan_steps` row this interval came from, when it came from one — the identity the
    /// runner writes a load adjustment back through.
    ///
    /// **Why it is here and not in a table beside the session.** `SessionRecord` carries the
    /// interval list and nothing else, so a side-map in the controller would be lost the moment the
    /// app relaunched and a resumed workout would be the one you could not adjust. Optional
    /// because the rests below have no step, because `PlanStep.id` is optional, and — the same rule
    /// every field of this type follows — because a snapshot or a record written by an older build
    /// has to decode. See `intensity` for the full statement of that rule.
    public let stepID: UUID?
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
        // Defaulted for the same reason `intensity` is: the fixtures in the tests hand-build
        // intervals to exercise the engine and the watch projection, and none of them is about
        // which plan row an interval came from. `PlanFlattener` and `withLoad` are the production
        // call sites, which is why `withLoad` sitting beside this declaration matters.
        stepID: UUID? = nil,
        // The one defaulted parameter: twelve fixtures hand-build intervals to test the engine and
        // the watch projection, and none of them is about effort. `PlanFlattener` and `withLoad`
        // are the production call sites, and `PlanFlattenerTests` pins that the flattener passes
        // this through.
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
        self.stepID = stepID
        self.intensity = intensity
    }

    // MARK: - Editing the load

    /// This interval with its load replaced, and **every other field untouched**.
    ///
    /// It lives here, beside the property list it copies, rather than with the adjustment that
    /// calls it. A full rebuild has to be kept in step with the fields above by hand, and a field
    /// this forgot would be dropped on precisely the intervals a user had adjusted — silently, and
    /// only for them. Anything added to `Interval` has to be added here, so this is where it will
    /// be seen: the one place a change to the shape of this type is already being made.
    ///
    /// Not `var targetWeightKg`: nothing else may change an interval in place, and an edit is
    /// applied to a whole step at once by `StepLoadEdit.applied(to:)`, which replaces rather than
    /// mutates.
    public func withLoad(weightKg: Double?, intensity: Intensity?) -> Interval {
        Interval(
            index: index,
            kind: kind,
            name: name,
            mode: mode,
            duration: duration,
            reps: reps,
            targetWeightKg: weightKg,
            setIndex: setIndex,
            setCount: setCount,
            blockRound: blockRound,
            blockRoundCount: blockRoundCount,
            blockName: blockName,
            exerciseID: exerciseID,
            stepID: stepID,
            intensity: intensity
        )
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

    /// Whether `contextLabel` above is currently carrying **this interval's effort**, rather than
    /// a set count, a round count or the block's name.
    ///
    /// It exists because the phone's effort arrows flank the line the effort is already on rather
    /// than adding a second one saying the same word — so the runner has to know which of the four
    /// things that line is. The two are two expressions of one precedence and live next to each
    /// other for that reason; `SessionScreenTests` asserts they agree.
    ///
    /// The set count wins first, so a multi-set step hides its effort from that line — which is a
    /// documented and deliberate precedence, not something the arrows may quietly change.
    public var contextLabelIsIntensity: Bool {
        intensity != nil && setCount <= 1
    }
}

/// One implementation, shared by `PlanStep` (the prescription) and `Interval` (what actually
/// runs), so the two cannot drift apart in how they read.
public enum MeasurementFormat {

    /// Whole numbers lose their trailing ".0"; halves keep theirs.
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// The whole second the countdown is *showing* — the number `clock(remaining:)` draws.
    ///
    /// **One function, because a cue is for the second on the screen.** Both cue loops —
    /// `SessionController.fireCountdownCue` and `WatchLink.announce` — ask this rather than
    /// rounding a "3" of their own: the click that belongs to 0:03 has to play while the screen
    /// says 0:03, and the four instants `SessionSchedule` wakes a surface for are exactly the
    /// boundaries at which this value changes. Two roundings would eventually be two answers, and
    /// a countdown that disagrees with the clock beside it is the whole failure being fixed here.
    public static func countdownSecond(remaining: TimeInterval) -> Int {
        max(0, Int(remaining.rounded(.up)))
    }

    /// "1:05". Rounded **up**, so the clock only reaches 0:00 when the interval is really
    /// over — reading 0:00 while a second still remains looks like a stalled timer.
    public static func clock(remaining: TimeInterval) -> String {
        let total = countdownSecond(remaining: remaining)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func reps(_ value: Int?) -> String? {
        value.map { "\($0) reps" }
    }

    public static func weight(_ value: Double?) -> String? {
        value.map { "\(number($0)) kg" }
    }
}
