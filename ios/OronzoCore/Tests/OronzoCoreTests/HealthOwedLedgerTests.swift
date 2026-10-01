import XCTest
@testable import OronzoCore

final class HealthOwedLedgerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func workout(span: TimeInterval = 1_800) -> RecordableWorkout {
        RecordableWorkout(startedAt: t0, finishedAt: t0.addingTimeInterval(span))
    }

    private func entry(
        id: UUID = UUID(),
        planName: String = "Push A",
        createdAt: Date? = nil
    ) -> HealthOwedEntry {
        HealthOwedEntry(
            id: id,
            planName: planName,
            workout: workout(),
            createdAt: createdAt ?? t0
        )
    }

    // MARK: - When Health should be asked again

    func testAFreshEntryIsRetryable() {
        XCTAssertTrue(entry().isRetryable(at: t0))
    }

    func testAnEntryBelowTheAttemptLimitIsStillRetryable() {
        var owed = entry()
        owed.recordAttempt(at: t0)
        owed.recordAttempt(at: t0)

        XCTAssertTrue(owed.isRetryable(at: t0.addingTimeInterval(3600)))
    }

    /// The limit is a count of attempts, and spending them is what ends an entry — not the passage
    /// of time, which is why this one is well inside the age window and still refused.
    func testAnEntryAtTheAttemptLimitIsNotRetryable() {
        var owed = entry()
        for _ in 0..<HealthOwedEntry.maximumAttempts { owed.recordAttempt(at: t0) }

        XCTAssertTrue(owed.isSpent(at: t0))
        XCTAssertFalse(owed.isRetryable(at: t0.addingTimeInterval(3600)))
    }

    /// The age rule is a window, not a deadline: an entry exactly on the edge is inside it.
    func testAnEntryExactlyAtTheAgeLimitIsRetryable() {
        let owed = entry(createdAt: t0)

        XCTAssertTrue(owed.isRetryable(at: t0.addingTimeInterval(HealthOwedEntry.maximumAge)))
    }

    func testAnEntryPastTheAgeLimitIsNotRetryable() {
        let owed = entry(createdAt: t0)

        XCTAssertFalse(owed.isRetryable(at: t0.addingTimeInterval(HealthOwedEntry.maximumAge + 1)))
    }

    /// The launch hook and the first `.active` of the same launch both fire within a second of each
    /// other, and one attempt covers the two of them.
    func testAnAttemptSecondsAgoIsNotRepeated() {
        var owed = entry()
        owed.recordAttempt(at: t0)

        XCTAssertFalse(owed.isRetryable(at: t0.addingTimeInterval(1)))
    }

    func testAnAttemptPastTheMinimumIntervalIsRepeated() {
        var owed = entry()
        owed.recordAttempt(at: t0)

        XCTAssertTrue(owed.isRetryable(at: t0.addingTimeInterval(HealthOwedEntry.minimumRetryInterval)))
    }

    /// A clock that moved backwards must not make an entry look ancient, and must not make a stamp
    /// look so old that it is retried instantly either. Both come out of the same subtraction: a
    /// future date gives a negative age and a negative interval.
    func testAClockBehindTheEntryDoesNotStrandIt() {
        let owed = entry(createdAt: t0.addingTimeInterval(60))

        XCTAssertTrue(owed.isRetryable(at: t0))
    }

    func testAnAttemptStampedInTheFutureIsTreatedAsTooSoon() {
        var owed = entry(createdAt: t0)
        owed.recordAttempt(at: t0.addingTimeInterval(60))

        XCTAssertFalse(owed.isRetryable(at: t0))
    }

    // MARK: - The two facts the HealthKit retry rests on

    /// Every attempt must arrive with a version greater than the last, because Apple's header
    /// documents exactly one rule — a save replaces an existing sample with the same identifier
    /// *if the new sample has a greater version* — and says nothing about the equal case.
    func testTheVersionClimbsWithEveryAttempt() {
        var owed = entry()
        var versions: [Int] = []

        for _ in 0..<HealthOwedEntry.maximumAttempts {
            // Written down before the attempt, which is what keeps it monotonic across a crash.
            versions.append(owed.nextVersion)
            owed.recordAttempt(at: t0)
        }

        XCTAssertEqual(versions, [1, 2, 3])
        XCTAssertEqual(Set(versions).count, versions.count, "a repeated version is the one thing that could duplicate")
    }

    func testRecordingAnAttemptCountsAndStampsIt() {
        var owed = entry()

        owed.recordAttempt(at: t0)

        XCTAssertEqual(owed.attempts, 1)
        XCTAssertEqual(owed.lastAttemptAt, t0)
    }

    /// A replay hands Health a workout rebuilt from the entry's own dates — there is nowhere else
    /// for it to come from, since the session that produced it is long gone by then.
    func testAReplayCarriesTheEntriesOwnSpan() {
        var owed = entry()
        owed.recordAttempt(at: t0)

        XCTAssertEqual(owed.workout.startedAt, t0)
        XCTAssertEqual(owed.workout.finishedAt, t0.addingTimeInterval(1_800))
    }

    // MARK: - The ledger

    func testALedgerRoundTripsThroughJSON() throws {
        var ledger = HealthOwedLedger(entries: [entry(planName: "Push A")])
        var attempted = entry(planName: "Pull B")
        attempted.recordAttempt(at: t0)
        attempted.recordAttempt(at: t0.addingTimeInterval(60))
        ledger.insert(attempted)

        let data = try JSONEncoder().encode(ledger)
        let restored = try JSONDecoder().decode(HealthOwedLedger.self, from: data)

        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.entry(attempted.id)?.attempts, 2)
    }

    /// A fresh entry has never been attempted, so its `lastAttemptAt` is absent from the JSON. That
    /// is the shape a retry reads back, and it must not be mistaken for an undecodable file.
    func testAnEntryThatHasNeverBeenAttemptedDecodesWithoutAnAttemptStamp() throws {
        let ledger = HealthOwedLedger(entries: [entry()])
        let data = try JSONEncoder().encode(ledger)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("lastAttemptAt"))

        let restored = try JSONDecoder().decode(HealthOwedLedger.self, from: data)

        XCTAssertEqual(restored.entries.first?.attempts, 0)
        XCTAssertNil(restored.entries.first?.lastAttemptAt)
    }

    /// The second resolution of one workout must not leave two entries behind.
    func testInsertingTheSameIdentityTwiceLeavesOneEntry() {
        let id = UUID()
        var ledger = HealthOwedLedger()
        ledger.insert(entry(id: id, planName: "Push A"))
        ledger.insert(entry(id: id, planName: "Push A"))

        XCTAssertEqual(ledger.entries.count, 1)
    }

    /// Resolving an entry that is already gone — a retry racing a removal — is not an error.
    func testReplacingAnEntryThatIsNoLongerThereDoesNothing() {
        var ledger = HealthOwedLedger()
        var owed = entry()
        owed.recordAttempt(at: t0)

        ledger.replace(owed)

        XCTAssertTrue(ledger.entries.isEmpty)
    }

    func testRemovingAnEntryLeavesTheOthersAlone() {
        let kept = entry(planName: "Push A")
        let removed = entry(planName: "Pull B")
        var ledger = HealthOwedLedger(entries: [kept, removed])

        ledger.remove(removed.id)

        XCTAssertEqual(ledger.entries, [kept])
    }

    func testOnlyEntriesInsideThePolicyAreOffered() {
        var spent = entry(planName: "Push A")
        for _ in 0..<HealthOwedEntry.maximumAttempts { spent.recordAttempt(at: t0) }
        let fresh = entry(planName: "Pull B")
        let ancient = entry(planName: "Legs C", createdAt: t0.addingTimeInterval(-HealthOwedEntry.maximumAge - 1))
        let ledger = HealthOwedLedger(entries: [spent, fresh, ancient])

        XCTAssertEqual(ledger.retryable(at: t0).map(\.id), [fresh.id])
    }

    /// Oldest first, so a ledger that somehow holds two obligations resolves them in the order they
    /// were taken on.
    func testTheLedgerOffersItsOldestObligationFirst() {
        let older = entry(planName: "Push A", createdAt: t0)
        let newer = entry(planName: "Pull B", createdAt: t0.addingTimeInterval(600))

        XCTAssertEqual(HealthOwedLedger(entries: [newer, older]).retryable(at: t0).map(\.planName), ["Push A", "Pull B"])
    }

    func testPruningForgetsEntriesPastTheHorizon() {
        let kept = entry(planName: "Push A")
        let forgotten = entry(planName: "Pull B", createdAt: t0.addingTimeInterval(-HealthOwedEntry.pruneAge - 1))
        var ledger = HealthOwedLedger(entries: [kept, forgotten])

        ledger.prune(at: t0)

        XCTAssertEqual(ledger.entries, [kept])
    }

    /// A file written by a later build is discarded rather than half-read — `SessionRecord`'s rule,
    /// for the same reason: being wrong about Health is worse than being empty.
    func testALedgerFromANewerSchemaIsRefused() {
        let json = """
        {"schema": \(HealthOwedLedger.schema + 1), "entries": []}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HealthOwedLedger.self, from: Data(json.utf8)))
    }
}
