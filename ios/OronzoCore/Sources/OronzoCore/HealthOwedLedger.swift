import Foundation

/// A finished workout that Apple Health has not confirmed, written down so it can be offered again.
///
/// **Why this exists.** A session that ends with the phone locked is the app's ordinary case, and
/// `HKWorkoutBuilder.finishWorkout()` answers it with a nil workout and *no error* — which Apple's
/// header documents as a save that happened ("the workout sample is not available because the
/// device is locked"), and which the field has now also produced as a save that did not. The two
/// are indistinguishable from inside the app, so the app does not try to tell them apart. It makes
/// the outcome **converge** instead: the obligation is written down here, and offered again when
/// the phone is unlocked, which is exactly when the answer stops being ambiguous.
///
/// **The safety property is not in this file.** Nothing here can prevent a retry from writing a
/// second copy of a workout — that is HealthKit's job, through `HKMetadataKeySyncIdentifier` and
/// `HKMetadataKeySyncVersion` (see `HealthWriteQueue` and the ADR in `docs/decisions.md`). What
/// this file guarantees is the one thing the identifier scheme needs: **an entry's `id` never
/// changes, and the version sent with each attempt strictly increases.** `nextVersion` derives
/// from the attempt count, which is written down *before* the attempt, so it stays monotonic even
/// across a crash.
///
/// Like `RecordableWorkout` and `SessionSchedule`, this is a pure rule with no clock of its own:
/// the caller has the time, this has the rule, and `swift test` settles it on macOS in a second.
public struct HealthOwedEntry: Codable, Equatable, Sendable {

    /// How many times one workout may be offered to Health before the app stops.
    ///
    /// **Three, because the *second* attempt is the one that matters.** The failure this exists for
    /// is a session that ended with the phone locked; the cure is the phone being unlocked, and the
    /// attempt that follows is the one with an ordinary chance of landing. The third is the
    /// backstop for a phone that was put down again before Health answered. A structural failure —
    /// a revoked permission, say — burns all three and stops, which is the point of having a limit
    /// rather than retrying a write that cannot succeed on every foreground for the rest of time.
    public static let maximumAttempts = 3

    /// After this, an entry is left alone.
    ///
    /// **This bounds the file, not HealthKit** — a backdated workout is a supported thing to save
    /// (the builder's own header says it exists "to create a workout that occurred in the past").
    /// It is here so an obligation from a phone that was off for a week does not arrive as a
    /// surprise, and because the attempts above will have been spent long before it.
    public static let maximumAge: TimeInterval = 48 * 60 * 60

    /// The floor between two attempts on the same entry.
    ///
    /// Deliberately small. It is not here to space retries out in any meaningful sense — it is here
    /// because the launch hook and the first `.active` of the same launch can both fire within a
    /// second of each other, and one attempt is enough for both. Ten seconds is far below the
    /// thirty-plus it takes a person to unlock a phone that just finished a workout, which is the
    /// attempt that must not be swallowed.
    public static let minimumRetryInterval: TimeInterval = 10

    /// How long a spent entry is kept before the ledger forgets it.
    ///
    /// Long, because a spent entry is the *only* record that a workout may be missing from Health —
    /// the summary is gone and the log rolls. Thirty days is the point at which it stops being
    /// actionable and starts being a file that only grows.
    public static let pruneAge: TimeInterval = 30 * 24 * 60 * 60

    /// The workout's identity, in this app and in Health.
    ///
    /// **It is the `HKMetadataKeySyncIdentifier` value, so it must never change.** A different id
    /// is a different workout to HealthKit, and the whole reason a retry cannot duplicate is that
    /// every attempt for one entry arrives under this same identifier.
    public let id: UUID

    /// Kept so a ledger line — in a log, or in a future screen — can name the workout without the
    /// plan it came from.
    public let planName: String

    /// The span Health is told. Nothing else about the session is here on purpose: the workout is
    /// two dates, and every other fact about the session belongs to the history write.
    public let startedAt: Date
    public let finishedAt: Date

    /// When the app took on the obligation. The age rule is measured from here.
    public let createdAt: Date

    public private(set) var attempts: Int
    public private(set) var lastAttemptAt: Date?

    /// Only builds from a workout that has **already** passed `RecordableWorkout`'s bar — the
    /// caller creates one of these after that decision, never before it.
    public init(
        id: UUID = UUID(),
        planName: String,
        workout: RecordableWorkout,
        createdAt: Date
    ) {
        self.id = id
        self.planName = planName
        self.startedAt = workout.startedAt
        self.finishedAt = workout.finishedAt
        self.createdAt = createdAt
        self.attempts = 0
        self.lastAttemptAt = nil
    }

    /// The payload a retry replays.
    ///
    /// **The three-minute bar is deliberately not re-applied.** It was decided once, on the active
    /// time the session actually contained; an entry carries only the span, and the span of a
    /// session with a pause in it is *longer* than the work it held — so re-deriving eligibility
    /// from a span would get the rule backwards.
    public var workout: RecordableWorkout {
        RecordableWorkout(startedAt: startedAt, finishedAt: finishedAt)
    }

    /// The `HKMetadataKeySyncVersion` to send with the next attempt.
    ///
    /// **Strictly greater than every version this entry has ever sent**, and that is the whole
    /// design. Apple's header documents exactly one rule — a save replaces an existing sample with
    /// the same identifier *if the new sample has a greater version* — and says nothing about the
    /// equal case, so the equal case is not relied on. A version that only ever climbs means each
    /// attempt either creates the workout or replaces the previous identical copy: never a second.
    public var nextVersion: Int { attempts + 1 }

    /// Whether Health should be offered this workout again.
    public func isRetryable(at now: Date) -> Bool {
        guard !isSpent(at: now) else { return false }
        guard let lastAttemptAt else { return true }
        // A stamp in the future — the clock moved back — is "too soon" rather than "long ago", and
        // the subtraction gets that right on its own: the interval is negative and fails the test.
        return now.timeIntervalSince(lastAttemptAt) >= Self.minimumRetryInterval
    }

    /// Whether the app has finished with this entry — by spending its attempts or by outliving the
    /// window — and will never offer it again.
    ///
    /// **Spent is not the same as absent.** An exhausted entry may still be a workout that Health
    /// has; what it means is that *this app has stopped asking*. Every line written about one has
    /// to say it that way.
    public func isSpent(at now: Date) -> Bool {
        attempts >= Self.maximumAttempts || age(at: now) > Self.maximumAge
    }

    /// Whether the ledger should forget this entry entirely.
    public func isForgettable(at now: Date) -> Bool {
        now.timeIntervalSince(createdAt) > Self.pruneAge
    }

    /// Counts an attempt and stamps it.
    ///
    /// **Called before the attempt, not after it** — the version sent must already be written down
    /// if the app dies mid-write, or the next attempt could reuse it. Spending an attempt on a save
    /// that never happened costs one of three; reusing a version could cost a duplicate.
    public mutating func recordAttempt(at now: Date) {
        attempts += 1
        lastAttemptAt = now
    }

    /// Age never negative: a clock that moved backwards must not make a fresh entry look old.
    private func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(createdAt))
    }
}

/// Every workout the app still owes Apple Health, as one value.
///
/// Held as a value rather than a live object so the file that stores it stays dumb — the writer and
/// the reader are on the same actor and the file is the only source of truth, which is the argument
/// `SessionRecordFile` already makes at length.
///
/// `schema` is written and checked for the same reason `SessionRecord` does it: a file written by a
/// later build is discarded rather than half-read, which is cheaper than being wrong about Health.
public struct HealthOwedLedger: Codable, Equatable, Sendable {

    public static let schema = 1

    public private(set) var entries: [HealthOwedEntry]

    public init(entries: [HealthOwedEntry] = []) {
        self.entries = entries
    }

    public func entry(_ id: UUID) -> HealthOwedEntry? {
        entries.first { $0.id == id }
    }

    /// The entries due an attempt, oldest first — the order a single-user ledger is read in.
    public func retryable(at now: Date) -> [HealthOwedEntry] {
        entries
            .filter { $0.isRetryable(at: now) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Adds an entry, replacing any with the same id.
    ///
    /// Replacing rather than appending is what makes a double-resolve idempotent: the second
    /// resolution of one workout cannot leave two entries behind.
    public mutating func insert(_ entry: HealthOwedEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    /// Writes back an entry that has just moved, e.g. one that counted an attempt. A no-op for an
    /// entry that is no longer there — a resolve racing a removal is not an error.
    public mutating func replace(_ entry: HealthOwedEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Forgets entries past `HealthOwedEntry.pruneAge`, spent or not.
    public mutating func prune(at now: Date) {
        entries.removeAll { $0.isForgettable(at: now) }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case schema
        case entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(Int.self, forKey: .schema)
        guard schema <= Self.schema else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "ledger schema \(schema) is newer than this build understands (\(Self.schema))"
            )
        }
        self.entries = try container.decode([HealthOwedEntry].self, forKey: .entries)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Written explicitly: a synthesised encoder would omit it, and the check above would then
        // be reading a key that is never there.
        try container.encode(Self.schema, forKey: .schema)
        try container.encode(entries, forKey: .entries)
    }
}
