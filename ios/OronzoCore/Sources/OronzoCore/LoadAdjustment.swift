import Foundation

/// A step's load as the user has left it: the value the runner's arrows move, and the value
/// Adjust writes back to `plan_steps`.
///
/// It belongs to a **step**, not an interval and not an exercise. An interval is one execution of a
/// step — one set, one side, one round — and the whole point of adjusting is that all of them move
/// together; an exercise can appear in several steps of one plan at different loads, which is why
/// `exerciseID` would be the wrong key. `stepID` is what `PlanFlattener` carries across for it.
///
/// The value is *pending* until Adjust commits it. Nothing here knows about the network or the
/// session — it is a value, and `SessionController` decides what to do with it.
public struct StepLoadEdit: Equatable, Sendable {

    /// The `plan_steps` row this edit belongs to.
    public let stepID: UUID

    /// The whole load, not a delta. An edit is seeded from the interval it was started on, so the
    /// fields the arrows did not touch already hold what the step prescribed — which is what makes
    /// `applying(to:)` a plain overwrite rather than a merge with its own set of rules.
    public var weightKg: Double?
    public var intensity: Intensity?

    public init(stepID: UUID, weightKg: Double? = nil, intensity: Intensity? = nil) {
        self.stepID = stepID
        self.weightKg = weightKg
        self.intensity = intensity
    }

    /// Seeds an edit from the interval the user is on, so the arrows start from what is on screen.
    public init?(interval: Interval) {
        guard let stepID = interval.stepID else { return nil }
        self.init(stepID: stepID, weightKg: interval.targetWeightKg, intensity: interval.intensity)
    }

    /// Whether this edit is about the interval in front of the user.
    ///
    /// The runner's pending edit is discarded the moment the session moves onto a different step,
    /// and that is the whole of the test.
    public func applies(to interval: Interval) -> Bool {
        interval.stepID == stepID
    }

    /// The interval with this load, and every other field untouched.
    ///
    /// The rebuild itself is `Interval.withLoad` — it belongs beside the fields it copies, so that
    /// a field added to `Interval` and forgotten there is visible in the one place the type's shape
    /// is already changing.
    public func applying(to interval: Interval) -> Interval {
        interval.withLoad(weightKg: weightKg, intensity: intensity)
    }

    /// The whole list with this edit applied to every interval it is about.
    ///
    /// The one expression of "which intervals an adjustment moves", used both by the engine
    /// folding in a committed edit and by the controller showing a pending one. Two copies of this
    /// map would be two answers to the question the feature is entirely about.
    public func applied(to intervals: [Interval]) -> [Interval] {
        intervals.map { applies(to: $0) ? applying(to: $0) : $0 }
    }
}

/// What one tap of an arrow does.
///
/// A closed set of steps and a wrap, in one place and with no state: the runner asks what a tap
/// would produce and the tests ask the same question on macOS. Nothing here reads a screen, a
/// session or a clock.
public enum LoadDial {

    /// The smallest pair of plates worth a trip to the rack.
    public static let weightStep: Double = 2.5

    /// One tap on a weight arrow.
    ///
    /// **Floors at zero**, because `plan_steps.target_weight_kg` carries `check (>= 0)` — a
    /// negative weight is a request the database refuses, and the arrow would be offering
    /// something the save cannot keep. Rounded to two decimals on the way out, which is the
    /// column's own scale (`numeric(6, 2)`): repeatedly adding 2.5 to a value that is not itself
    /// on the half-kilo grid would otherwise drift, and what is displayed would stop matching what
    /// is written.
    public static func weight(_ current: Double, up: Bool) -> Double {
        let next = up ? current + weightStep : current - weightStep
        return max(0, (next * 100).rounded() / 100)
    }

    /// One tap on an effort arrow, **wrapping**: past `hard` is `low` again, and below `low` is
    /// `hard`. A closed loop rather than two controls that stop, so the two arrows stay the
    /// inverse of each other and the three words are one cycle in both directions.
    ///
    /// The order cycled is `Intensity.allCases`, whose declaration order is effort-ascending and
    /// is documented as load-bearing on the enum itself.
    public static func intensity(_ current: Intensity, up: Bool) -> Intensity {
        let all = Intensity.allCases
        guard let index = all.firstIndex(of: current) else { return current }
        let next = up ? index + 1 : index - 1
        return all[(next + all.count) % all.count]
    }
}
