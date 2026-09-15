import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case inProgress = "in_progress"
    case completed
    case abandoned
}

public enum OutcomeStatus: String, Codable, Sendable {
    case pending
    case completed
    case skipped
    /// Never reached before the session ended.
    case notReached = "not_reached"
}

/// What happened on one interval. Only the *duration* is recorded — the engine measures it
/// itself. How many reps you actually did, and at what load, is not tracked: the runner has
/// no way to enter it, so those columns would only ever be null.
public struct IntervalOutcome: Equatable, Sendable {
    public var status: OutcomeStatus
    public var duration: TimeInterval?

    public init(status: OutcomeStatus = .pending, duration: TimeInterval? = nil) {
        self.status = status
        self.duration = duration
    }
}

public enum Phase: Equatable, Sendable {
    case idle
    case running
    case paused
    case finished
}

public enum EngineEvent: Equatable, Sendable {
    case started(index: Int, end: Date?)
    case advanced(from: Int, to: Int)
    case paused(remaining: TimeInterval)
    case resumed(end: Date?)
    case finished
}

/// The session state machine.
///
/// Two decisions carry most of the weight here:
///
/// 1. **Time is anchored to an absolute `intervalEnd` Date, never a decrementing counter.**
///    A counter drifts and, worse, goes wrong the moment the app is suspended — which is
///    the normal case, with the phone in a pocket. Because the boundary is absolute, the
///    display is simply *correct* on the next render, and a long suspension resolves in a
///    single `.advanced` event rather than a burst of them.
///
/// 2. **Timed intervals advance themselves; rep intervals wait for a tap.** A rep interval
///    has no known length, so it has no end date and `tick` deliberately passes through it.
public struct ExecutionEngine: Sendable {

    public let intervals: [Interval]
    public private(set) var currentIndex: Int = 0
    public private(set) var phase: Phase = .idle
    /// Absolute end of the current interval. `nil` while paused, or on a rep interval.
    public private(set) var intervalEnd: Date?
    public private(set) var remainingWhenPaused: TimeInterval?
    public private(set) var startedAt: Date?
    public private(set) var finishedAt: Date?
    public private(set) var pausedTotal: TimeInterval = 0
    public private(set) var outcomes: [Int: IntervalOutcome]

    private var pausedAt: Date?

    public init(intervals: [Interval]) {
        self.intervals = intervals
        self.outcomes = Dictionary(uniqueKeysWithValues: intervals.map { ($0.index, IntervalOutcome()) })
    }

    // MARK: - Derived state

    public var current: Interval? {
        intervals.indices.contains(currentIndex) ? intervals[currentIndex] : nil
    }

    /// Remaining time on the current interval, or `nil` for a rep interval (which has no
    /// end) — the UI shows a count-up or just the rep target in that case.
    public func remaining(at now: Date) -> TimeInterval? {
        switch phase {
        case .paused: return remainingWhenPaused
        case .running: return intervalEnd.map { max(0, $0.timeIntervalSince(now)) }
        default: return nil
        }
    }

    /// Elapsed wall-clock time of the session, excluding pauses.
    public func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let end = finishedAt ?? now
        return max(0, end.timeIntervalSince(startedAt) - pausedTotal)
    }

    // MARK: - Transitions

    @discardableResult
    public mutating func start(at now: Date) -> [EngineEvent] {
        guard phase == .idle, !intervals.isEmpty else { return [] }
        startedAt = now
        currentIndex = 0
        phase = .running
        intervalEnd = intervals[0].duration.map { now.addingTimeInterval($0) }
        return [.started(index: 0, end: intervalEnd)]
    }

    /// Advances past any automatic intervals whose time has elapsed.
    ///
    /// Coalesces: if the app was suspended for five minutes across three timed intervals,
    /// this emits **one** `.advanced(from:to:)`, not three.
    @discardableResult
    public mutating func tick(now: Date) -> [EngineEvent] {
        guard phase == .running, let end = intervalEnd, now >= end else { return [] }

        let from = currentIndex
        var index = from
        var boundary = end

        while true {
            // Nothing left after the current interval — the session is over.
            guard index + 1 < intervals.count else {
                closeAutomatic(from: from, to: index)
                outcomes[index] = IntervalOutcome(status: .completed, duration: intervals[index].duration)
                finishedAt = now
                phase = .finished
                intervalEnd = nil
                // No `.advanced` here: the index does not change, and emitting one would
                // make the Watch redraw the same interval before clearing.
                return [.finished]
            }

            // The next interval is rep-based: it has no length, so hand control back.
            guard let nextDuration = intervals[index + 1].duration else {
                closeAutomatic(from: from, to: index + 1)
                currentIndex = index + 1
                intervalEnd = nil
                return [.advanced(from: from, to: index + 1)]
            }

            boundary = boundary.addingTimeInterval(nextDuration)
            index += 1
            if now < boundary { break }
        }

        closeAutomatic(from: from, to: index)
        currentIndex = index
        intervalEnd = boundary
        return [.advanced(from: from, to: index)]
    }

    /// Marks intervals `from..<to` as auto-completed, since their time elapsed.
    private mutating func closeAutomatic(from: Int, to: Int) {
        guard from < to else { return }
        for i in from..<to where outcomes[i]?.status == .pending {
            outcomes[i] = IntervalOutcome(status: .completed, duration: intervals[i].duration)
        }
    }

    @discardableResult
    public mutating func pause(at now: Date) -> [EngineEvent] {
        guard phase == .running else { return [] }
        remainingWhenPaused = intervalEnd.map { max(0, $0.timeIntervalSince(now)) }
        pausedAt = now
        intervalEnd = nil
        phase = .paused
        return [.paused(remaining: remainingWhenPaused ?? 0)]
    }

    @discardableResult
    public mutating func resume(at now: Date) -> [EngineEvent] {
        guard phase == .paused else { return [] }
        if let pausedAt { pausedTotal += now.timeIntervalSince(pausedAt) }
        self.pausedAt = nil
        phase = .running
        // A rep interval keeps no end date; anything else resumes from where it stopped.
        intervalEnd = remainingWhenPaused.map { now.addingTimeInterval($0) }
        remainingWhenPaused = nil
        return [.resumed(end: intervalEnd)]
    }

    /// Completes the current interval now and moves on. Also used to skip.
    @discardableResult
    public mutating func advance(at now: Date, skipped: Bool = false) -> [EngineEvent] {
        guard phase == .running || phase == .paused, let current else { return [] }

        outcomes[current.index] = {
            var outcome = outcomes[current.index] ?? IntervalOutcome()
            outcome.status = skipped ? .skipped : .completed
            if outcome.duration == nil, !skipped { outcome.duration = current.duration }
            return outcome
        }()

        let next = current.index + 1
        guard next < intervals.count else {
            finishedAt = now
            phase = .finished
            intervalEnd = nil
            return [.finished]
        }

        currentIndex = next

        if phase == .paused {
            remainingWhenPaused = intervals[next].duration
            intervalEnd = nil
        } else {
            intervalEnd = intervals[next].duration.map { now.addingTimeInterval($0) }
        }

        return [.advanced(from: current.index, to: next)]
    }

    /// Goes back one interval, discarding whatever was recorded for it.
    @discardableResult
    public mutating func goBack(at now: Date) -> [EngineEvent] {
        guard phase == .running || phase == .paused else { return [] }
        let target = max(0, currentIndex - 1)
        guard target != currentIndex else { return [] }

        outcomes[target] = IntervalOutcome()
        let from = currentIndex
        currentIndex = target

        if phase == .paused {
            remainingWhenPaused = intervals[target].duration
            intervalEnd = nil
        } else {
            intervalEnd = intervals[target].duration.map { now.addingTimeInterval($0) }
        }

        return [.advanced(from: from, to: target)]
    }

    /// Ends the session early, marking everything not yet reached.
    @discardableResult
    public mutating func abandon(at now: Date) -> CompletedSession {
        close(.abandoned, at: now)
    }

    /// Ends the session normally, marking anything not reached. Production reaches
    /// `.finished` through `tick`/`advance` instead; this exists for tests, which need to
    /// end a session mid-way and still get a `completed` snapshot.
    @discardableResult
    public mutating func finish(at now: Date) -> CompletedSession {
        close(.completed, at: now)
    }

    /// Shared tail of the two: everything unreached becomes `.notReached`, and the session
    /// is frozen. Only the status they hand to `snapshot` differs.
    private mutating func close(_ status: SessionStatus, at now: Date) -> CompletedSession {
        for interval in intervals where outcomes[interval.index]?.status == .pending {
            outcomes[interval.index] = IntervalOutcome(status: .notReached)
        }
        finishedAt = now
        phase = .finished
        intervalEnd = nil
        return snapshot(status: status)
    }

    /// The rows to write to `sessions` + `session_steps`.
    public func snapshot(status: SessionStatus) -> CompletedSession {
        let end = finishedAt ?? startedAt ?? Date()
        let start = startedAt ?? end

        return CompletedSession(
            startedAt: start,
            finishedAt: end,
            totalDuration: elapsed(at: end),
            status: status,
            steps: intervals.map { interval in
                let outcome = outcomes[interval.index] ?? IntervalOutcome()
                return CompletedStep(
                    position: interval.index,
                    setIndex: interval.setIndex,
                    blockRound: interval.blockRound,
                    blockName: interval.blockName,
                    kind: interval.kind,
                    exerciseID: interval.exerciseID,
                    exerciseName: interval.name,
                    plannedMode: interval.mode,
                    plannedDuration: interval.duration,
                    plannedReps: interval.reps,
                    plannedWeightKg: interval.targetWeightKg,
                    actualDuration: outcome.duration,
                    status: outcome.status
                )
            }
        )
    }
}

// MARK: - What gets logged

public struct CompletedSession: Equatable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let totalDuration: TimeInterval
    public let status: SessionStatus
    public let steps: [CompletedStep]
}

/// Snapshots the exercise *name* and the planned values, so that history still reads
/// correctly after the plan or the exercise is later renamed or deleted.
public struct CompletedStep: Equatable, Sendable {
    public let position: Int
    /// Which set of the exercise this was (1-based).
    public let setIndex: Int
    /// Which round of the enclosing block this was (1-based).
    public let blockRound: Int
    public let blockName: String?
    public let kind: StepKind
    public let exerciseID: UUID?
    public let exerciseName: String
    public let plannedMode: StepMode?
    public let plannedDuration: TimeInterval?
    public let plannedReps: Int?
    public let plannedWeightKg: Double?
    public let actualDuration: TimeInterval?
    public let status: OutcomeStatus
}
