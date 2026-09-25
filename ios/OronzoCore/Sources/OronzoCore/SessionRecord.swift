import Foundation

/// A workout, written down.
///
/// **This exists because the phone could not answer one question honestly.** Until now the only
/// thing that knew a session was running was a `weak` reference held by the watch link, set when
/// a controller started and cleared when one was torn down (`PhoneConnectivity.advertised`). That
/// is not the same as knowing a workout is going — it is knowing whether *this process* happens
/// to be holding an object that says so. A relaunched app holds nothing, so it answered the watch
/// with "nothing is running" while the workout was still on. The wrist read **"No workout"** and
/// the watch's Next / Previous / Pause buttons went dead with it, because there was no longer a
/// session to route them to. That is the failure this project has now chased five times
/// (`docs/runbook.md`); it is reproducible on a desk in under a minute, and this type is the fix.
///
/// So: the engine's whole state, as a value, written to disk on every change and read back on
/// launch. The phone can then *know*, answer the watch from what it knows, and resume the workout
/// rather than destroying it.
///
/// **It carries the interval list, and that is deliberate.** The same argument as
/// `SessionSnapshot`: the record has to be self-contained, so a workout can be answered and
/// resumed even if the plan has since been edited or deleted on the server. It is also what makes
/// the record and the wire incapable of disagreeing — they are the same intervals out of the same
/// engine, written in the same closed sequence.
///
/// This is a **phone-local file**, not a wire message. It is not a licence to send the watch
/// incremental updates: `SessionSnapshot` still goes whole, every time, for the reasons spelled
/// out there.
public struct SessionRecord: Codable, Equatable, Sendable {

    /// The record's own format. Separate from `WireProtocol`: this is a file one app writes and
    /// reads, where that is a conversation between two apps installed separately.
    public static let schema = 1

    /// How long a written-down session stays resumable.
    ///
    /// **This bound is doing real work.** A timed plan self-terminates on restore — the engine's
    /// `tick` walks past every elapsed interval and lands in `.finished` — but a **rep** interval
    /// does not: it has no length, so nothing moves it on, and it would sit there forever waiting
    /// for a tap. The age window is the only thing that stops a forgotten record from resuming a
    /// workout from the middle of last week. Six hours is comfortably past the watch's own
    /// one-hour `physical-therapy` ceiling, so a session that is genuinely still going is never
    /// cut off by this.
    public static let maximumAge: TimeInterval = 6 * 60 * 60

    public let planID: UUID
    public let planName: String
    /// Carried whole. See the type's doc comment.
    public let intervals: [Interval]
    public let startedAt: Date
    public let currentIndex: Int
    public let phase: Phase
    public let intervalEnd: Date?
    public let remainingWhenPaused: TimeInterval?
    public let pausedTotal: TimeInterval
    /// When the pause now in progress began, if there is one.
    ///
    /// Carried because a paused session is a **live** session, and the gap between the pause and
    /// the restore is time the phone spent dead rather than time spent exercising. Without this
    /// the restore would have to guess, and the guess lands in `totalDuration` and then in
    /// history — a wrong number about a workout, written down permanently, from a field that was
    /// simply not recorded.
    public let pausedAt: Date?
    public let finishedAt: Date?
    public let outcomes: [Int: IntervalOutcome]
    /// When this was last written. The age rule keys off this rather than `startedAt`, so a long
    /// workout is not aged out for having started long ago.
    public let savedAt: Date

    public init(engine: ExecutionEngine, planID: UUID, planName: String, savedAt: Date) {
        self.planID = planID
        self.planName = planName
        self.intervals = engine.intervals
        self.startedAt = engine.startedAt ?? savedAt
        self.currentIndex = engine.currentIndex
        self.phase = engine.phase
        self.intervalEnd = engine.intervalEnd
        self.remainingWhenPaused = engine.remainingWhenPaused
        self.pausedTotal = engine.pausedTotal
        self.pausedAt = engine.pausedAt
        self.finishedAt = engine.finishedAt
        self.outcomes = engine.outcomes
        self.savedAt = savedAt
    }

    // MARK: - Decoding

    /// Written out by hand for the same reason `SessionState`'s is: **a record outlives the build
    /// that wrote it.** A workout is written down, the app is updated, and the record is still
    /// sitting there on the next launch — so a field added later must not make it unreadable.
    ///
    /// The split is not arbitrary. What is **required** is exactly what makes the record
    /// meaningless without it: which plan, which intervals, where in them, and whether it had
    /// started. What is **tolerated** is every detail whose absence only loses something small —
    /// an end date, a held clock, a paused total, the outcomes recorded so far. That way adding a
    /// new detail in a later build is forward-compatible for free, which is the property that
    /// keeps this from becoming the next thing to cost a morning.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Refuses a format it does not know rather than guessing at its shape. Absent means the
        // first format, which is correct: anything written before this field existed is schema 1.
        let schema = try container.decodeIfPresent(Int.self, forKey: .schema) ?? Self.schema
        guard schema <= Self.schema else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "record schema \(schema) is newer than this build understands (\(Self.schema))"
            )
        }

        planID = try container.decode(UUID.self, forKey: .planID)
        planName = try container.decode(String.self, forKey: .planName)
        intervals = try container.decode([Interval].self, forKey: .intervals)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        phase = try container.decode(Phase.self, forKey: .phase)
        savedAt = try container.decode(Date.self, forKey: .savedAt)

        intervalEnd = try container.decodeIfPresent(Date.self, forKey: .intervalEnd)
        remainingWhenPaused = try container.decodeIfPresent(TimeInterval.self, forKey: .remainingWhenPaused)
        pausedTotal = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedTotal) ?? 0
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        outcomes = try container.decodeIfPresent([Int: IntervalOutcome].self, forKey: .outcomes) ?? [:]
    }

    /// Encoded explicitly so `schema` is always written, even though it is never stored — the
    /// synthesised encoder would omit it and every record would come back as "schema unknown".
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schema, forKey: .schema)
        try container.encode(planID, forKey: .planID)
        try container.encode(planName, forKey: .planName)
        try container.encode(intervals, forKey: .intervals)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(currentIndex, forKey: .currentIndex)
        try container.encode(phase, forKey: .phase)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encodeIfPresent(intervalEnd, forKey: .intervalEnd)
        try container.encodeIfPresent(remainingWhenPaused, forKey: .remainingWhenPaused)
        try container.encode(pausedTotal, forKey: .pausedTotal)
        try container.encodeIfPresent(pausedAt, forKey: .pausedAt)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try container.encode(outcomes, forKey: .outcomes)
    }

    private enum CodingKeys: String, CodingKey {
        case schema, planID, planName, intervals, startedAt, currentIndex, phase, savedAt
        case intervalEnd, remainingWhenPaused, pausedTotal, pausedAt, finishedAt, outcomes
    }

    // MARK: - Answering the watch

    /// The session's position, in the shape the wire wants.
    public var state: SessionState {
        SessionState(
            currentIndex: currentIndex,
            isPaused: phase == .paused,
            isFinished: phase == .finished,
            intervalEnd: intervalEnd,
            remainingWhenPaused: remainingWhenPaused,
            finishedAt: finishedAt
        )
    }

    /// The complete message the watch should be showing. Never partial — see `SessionSnapshot`.
    public var snapshot: SessionSnapshot {
        SessionSnapshot(
            planName: planName,
            intervals: intervals,
            startedAt: startedAt,
            state: state
        )
    }

    /// The same thing, in the shape the link sends. So a record can answer the watch directly.
    public var message: WatchMessage { .session(snapshot) }

    // MARK: - Which records count

    /// Whether a workout is genuinely still going, as of `now`.
    ///
    /// **One rule, used by both answering and resuming**, and that is the point. The phone must
    /// never tell the watch "a workout is running" about a session it would then refuse to
    /// resume — two halves of the same app disagreeing about what is happening is the exact
    /// failure this project keeps paying for, and a lesson bought five times over.
    public func isLive(at now: Date) -> Bool {
        guard !intervals.isEmpty, now.timeIntervalSince(savedAt) <= Self.maximumAge else { return false }
        return phase == .running || phase == .paused
    }

    /// Whether this is still worth telling the watch about.
    ///
    /// Everything `isLive` covers, plus a session that **finished** inside the window. A workout
    /// that ran its course while the phone was dead leaves a record whose `DONE` screen the watch
    /// is still drawing; answering `.sessionEnded` there would erase it, and answering with the
    /// snapshot keeps the screen — and the history write that a resume can still perform — alive.
    public func isPresentable(at now: Date) -> Bool {
        isLive(at: now) || (!intervals.isEmpty
            && now.timeIntervalSince(savedAt) <= Self.maximumAge
            && phase == .finished)
    }

    /// The record brought up to date, or `nil` when it cannot be restored.
    ///
    /// Goes **through** `ExecutionEngine` rather than re-deriving the position here, so the
    /// property that a suspension across three timed intervals resolves in a single `.advanced`
    /// is reused rather than reimplemented. That is also what guarantees answering the watch from
    /// a record can never rewind it: the projection from a stale anchor and from a fresh one
    /// agree, which `WatchProjectionTests` pins.
    public func advanced(to now: Date) -> SessionRecord? {
        guard var engine = ExecutionEngine(restoring: self) else { return nil }
        guard engine.phase == .running else { return self }
        _ = engine.tick(now: now)
        return SessionRecord(engine: engine, planID: planID, planName: planName, savedAt: now)
    }
}
