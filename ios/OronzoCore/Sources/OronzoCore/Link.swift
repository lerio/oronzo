import Foundation

// MARK: - What the phone tells the watch

/// The vocabulary between the two apps. Deliberately tiny: the watch is a display and a
/// remote, and the phone remains the single source of truth for what you actually did.
public enum WatchMessage: Codable, Sendable {
    /// Everything the watch needs, always complete.
    case session(SessionSnapshot)
    case sessionEnded
}

/// The whole picture: the plan, and where the session is within it.
///
/// This is ONE message rather than a "start" followed by "updates", and that is not a style
/// choice. The application context is a single slot — whatever you write last is all that
/// survives — so sending a start and then an update back to back leaves only the update. A
/// watch app that was asleep at that moment would wake to a position with no plan in it,
/// and sit there showing "no workout" while the phone thought it had been told everything.
/// Sending the plan every time costs a few kilobytes and removes that entire class of bug.
public struct SessionSnapshot: Codable, Sendable {
    public let planName: String
    public let intervals: [Interval]
    public let startedAt: Date
    public let state: SessionState
    /// Which build wrote this, so a mismatch can *say so* instead of being silent.
    ///
    /// **Optional, and that is what makes it safe in both directions.** This struct's decoder is
    /// synthesised, so an optional is `decodeIfPresent` by construction: a watch built before
    /// this field existed skips the key it does not know, and a watch built after it reads `nil`
    /// from a phone that predates it. Same mechanism, and the same rule, as
    /// `Interval.intensity` — see the argument written out there.
    ///
    /// **The version's job is to make a mismatch legible, not to prevent one.** Prevention is the
    /// optional-field rule above; a non-optional addition breaks every older build regardless of
    /// what this number says, and no amount of version negotiation will save it. All this can do
    /// is narrate the wreckage — which is worth having, because the wreckage is otherwise a watch
    /// reading "No workout" with nothing anywhere to explain why
    /// (`docs/runbook.md:241`, "cost several hours to find once").
    public let protocolVersion: Int?

    public init(
        planName: String,
        intervals: [Interval],
        startedAt: Date,
        state: SessionState,
        protocolVersion: Int? = WireProtocol.current
    ) {
        self.planName = planName
        self.intervals = intervals
        self.startedAt = startedAt
        self.state = state
        self.protocolVersion = protocolVersion
    }
}

/// What the two apps are speaking, and what to say when they are not speaking the same thing.
///
/// Exists because the two apps are **installed separately and updated separately**, and there is
/// no App Group, no shared bundle, and no way for either to see the other's version except by
/// asking. `docs/runbook.md` records the cost of not having this: a stale watch app, a healthy
/// phone, no error message anywhere, and hours spent finding it.
public enum WireProtocol {

    /// What this build speaks. Absent on the wire means "built before versioning existed".
    public static let current = 1

    /// The oldest build this one can still work with. Bumping this is a promise that everything
    /// older is genuinely unusable, which is a much stronger claim than adding a field.
    public static let minimum = 1

    /// How the peer differs from us, or `nil` when it does not.
    ///
    /// Returns a *direction* rather than a sentence, because the two surfaces have to phrase this
    /// differently and one of them is a watch face: the phone names a scheme to run, the watch
    /// names an app to update. Deciding the direction is the rule and belongs here; writing the
    /// words is the app's job.
    public static func mismatch(_ peerVersion: Int?) -> ProtocolMismatch? {
        guard let peerVersion else {
            // Never reported a version at all. That is not an error — it is exactly what a build
            // from before this field existed does, and it is the single most likely mismatch in
            // the field, because it is what happens after a re-sign that replaced one app and not
            // the other.
            return .peerIsOlder
        }
        if peerVersion < minimum { return .peerIsOlder }
        if peerVersion > current { return .peerIsNewer }
        return nil
    }
}

public enum ProtocolMismatch: Equatable, Sendable {
    /// The other app is older than this build, or predates versioning entirely.
    case peerIsOlder
    /// The other app is newer than this build, so this one is the one that needs updating.
    case peerIsNewer
}

public struct SessionState: Codable, Equatable, Sendable {
    public let currentIndex: Int
    public let isPaused: Bool
    public let isFinished: Bool
    /// Absolute end of the current interval. Absolute rather than "seconds remaining" is
    /// the whole point: the watch can count down from it without the phone having to send
    /// anything every second, and it stays correct across a suspension.
    public let intervalEnd: Date?
    public let remainingWhenPaused: TimeInterval?
    /// When the session actually ended, so the `DONE` screen can show a *total* rather than a
    /// number that grows every time the watch redraws. Nil while a session is running.
    public let finishedAt: Date?

    public init(
        currentIndex: Int,
        isPaused: Bool,
        isFinished: Bool,
        intervalEnd: Date?,
        remainingWhenPaused: TimeInterval?,
        finishedAt: Date? = nil
    ) {
        self.currentIndex = currentIndex
        self.isPaused = isPaused
        self.isFinished = isFinished
        self.intervalEnd = intervalEnd
        self.remainingWhenPaused = remainingWhenPaused
        self.finishedAt = finishedAt
    }

    /// Decoding is written out by hand to be **tolerant of a missing `finishedAt`**.
    ///
    /// The application context persists across launches, so a snapshot encoded by an earlier
    /// build can still be sitting there when a newer one starts. A synthesised decoder rejects
    /// it for the absent key and the watch shows nothing at all — which is precisely the trap
    /// `docs/known-issues.md` records for `Interval`, and which was observed happening on a real
    /// device during this slice. New optional fields must default rather than fail.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        isPaused = try container.decode(Bool.self, forKey: .isPaused)
        isFinished = try container.decode(Bool.self, forKey: .isFinished)
        intervalEnd = try container.decodeIfPresent(Date.self, forKey: .intervalEnd)
        remainingWhenPaused = try container.decodeIfPresent(TimeInterval.self, forKey: .remainingWhenPaused)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
    }
}

// MARK: - What the watch asks the phone to do

public enum WatchControl: String, Codable, Sendable {
    case next
    case previous
    case togglePause
    case finish
    /// "I have nothing to show — tell me where this session is."
    ///
    /// The phone has only ever *pushed*, and the watch has only ever listened. That works
    /// until a push goes missing, and every way it can go missing is silent: the write lands
    /// before the phone's `WCSession` finished activating, a snapshot is overwritten in the
    /// application context by a `sessionEnded` from a runner that is no longer the live one,
    /// or the watch resumes from a wrist-drop suspension without being handed the context it
    /// missed. The wrist then reads **"No workout"** for the rest of the workout, which is
    /// indistinguishable from the phone never having started one — the failure this project
    /// has now chased four times (see `docs/runbook.md`).
    ///
    /// So the watch can ask. The phone answers from whatever is *actually* running, which is
    /// what turns each of those from a permanently wrong screen into a sub-second recovery.
    case requestState
}

// MARK: - Encoding

/// The two sides encode through the same pair of calls, so they cannot disagree about dates.
///
/// Each call builds its own `JSONEncoder`/`JSONDecoder`, and that is deliberate rather than
/// overlooked: neither is `Sendable`, so hoisting them into a `static let` would be a shared
/// mutable object reachable from both actors — the same reasoning that keeps
/// `SessionLogger`'s formatter off a static. The cost is one allocation per message, and messages
/// are one per state change rather than one per tick.
public enum WireCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Keeping the watch honest while the phone is away

public enum WatchProjection {

    /// Where the session should be *now*, given the phone's last known position.
    ///
    /// The watch is sent the entire interval list, so it can keep counting through timed
    /// intervals with no further word from the phone — which is what lets it buzz your
    /// wrist with the phone in a locker. The phone's next message re-anchors it.
    ///
    /// A rep interval ends the walk: it has no length, so nothing can be assumed about when
    /// it finishes. The watch shows its target and waits for the phone to say otherwise.
    public static func project(
        intervals: [Interval],
        from index: Int,
        end: Date?,
        now: Date
    ) -> (index: Int, end: Date?) {
        guard intervals.indices.contains(index), var boundary = end else {
            return (index, end)
        }

        var current = index
        while now >= boundary {
            guard current + 1 < intervals.count else { break }

            let next = intervals[current + 1]
            current += 1

            guard let duration = next.duration else { return (current, nil) }
            boundary = boundary.addingTimeInterval(duration)
        }

        return (current, boundary)
    }
}
