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

    public init(planName: String, intervals: [Interval], startedAt: Date, state: SessionState) {
        self.planName = planName
        self.intervals = intervals
        self.startedAt = startedAt
        self.state = state
    }
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

    public init(
        currentIndex: Int,
        isPaused: Bool,
        isFinished: Bool,
        intervalEnd: Date?,
        remainingWhenPaused: TimeInterval?
    ) {
        self.currentIndex = currentIndex
        self.isPaused = isPaused
        self.isFinished = isFinished
        self.intervalEnd = intervalEnd
        self.remainingWhenPaused = remainingWhenPaused
    }
}

// MARK: - What the watch asks the phone to do

public enum WatchControl: String, Codable, Sendable {
    case next
    case previous
    case togglePause
    case finish
}

// MARK: - Encoding

/// One encoder/decoder pair for both sides, so they cannot disagree about dates.
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
