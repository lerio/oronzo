import XCTest
@testable import OronzoCore

/// The workout the phone writes down, and reads back.
///
/// This type exists because the phone could not previously answer one question honestly — "is a
/// workout running?" was `advertised != nil` on a weak reference, which is really "does this
/// *process* hold an object saying so". A relaunched app holds nothing, so it told the watch
/// "nothing is running" mid-workout and the wrist read **"No workout"**. Reproduced on paired
/// simulators before this file was written; see `docs/runbook.md`.
///
/// What these tests pin is the part that cannot be recovered from once it is wrong: a record that
/// **cannot be restored must never be half-applied**. A workout is the only thing here that is
/// not reproducible — the plan lives on a server, the history can be re-fetched, but what you
/// actually did exists exactly once, in this file, and only until it is saved. So every way a
/// record could describe something impossible is asserted to be refused outright.
final class SessionRecordTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let planID = UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!

    // MARK: - Fixtures

    private func timed(_ index: Int, _ seconds: TimeInterval) -> Interval {
        Interval(
            index: index, kind: .exercise, name: "Work \(index)", mode: .time, duration: seconds,
            reps: nil, targetWeightKg: nil, setIndex: 1, setCount: 1,
            blockRound: 1, blockRoundCount: 1, blockName: nil, exerciseID: nil
        )
    }

    private func rep(_ index: Int) -> Interval {
        Interval(
            index: index, kind: .exercise, name: "Press", mode: .reps, duration: nil,
            reps: 8, targetWeightKg: 20, setIndex: 1, setCount: 1,
            blockRound: 1, blockRoundCount: 1, blockName: nil, exerciseID: nil
        )
    }

    /// An engine part-way through a session of `count` one-minute intervals.
    private func engineMidSession(count: Int = 5, startedAt: Date? = nil) -> ExecutionEngine {
        var engine = ExecutionEngine(intervals: (0..<count).map { timed($0, 60) })
        _ = engine.start(at: startedAt ?? t0)
        return engine
    }

    private func record(_ engine: ExecutionEngine, savedAt: Date? = nil) -> SessionRecord {
        SessionRecord(engine: engine, planID: planID, planName: "Upper Body A", savedAt: savedAt ?? t0)
    }

    // MARK: - The disk format

    func testARecordRoundTripsThroughJSON() throws {
        var engine = engineMidSession()
        _ = engine.advance(at: t0.addingTimeInterval(60), skipped: true)

        let encoded = try WireCodec.encode(record(engine, savedAt: t0))
        let back = try WireCodec.decode(SessionRecord.self, from: encoded)

        XCTAssertEqual(back, record(engine, savedAt: t0), "the whole record survives the file")
    }

    /// The record is a file one build writes and another reads — the app is updated between a
    /// workout and the next launch onto the same record, which is the ordinary case rather than
    /// an exotic one. A field added later must therefore not make an existing record unreadable,
    /// or the update that adds it silently loses whatever workout was in flight.
    ///
    /// The key is stripped from a freshly-encoded record rather than hand-written, so this does
    /// not encode a guess about how the record nests — it removes exactly the field an older
    /// build would not have written.
    func testARecordWithoutTheNewestFieldStillDecodes() throws {
        var engine = engineMidSession()
        _ = engine.advance(at: t0.addingTimeInterval(60), skipped: true)

        let encoded = try WireCodec.encode(record(engine, savedAt: t0))
        let stripped = try JSONSerialization.data(
            withJSONObject: removing("finishedAt", from: try JSONSerialization.jsonObject(with: encoded))
        )

        let back = try WireCodec.decode(SessionRecord.self, from: stripped)

        XCTAssertEqual(back.intervals.count, 5, "the plan survives a field it never knew about")
        XCTAssertEqual(back.currentIndex, 1)
        XCTAssertNil(back.finishedAt)
    }

    /// A record from a *newer* build is refused rather than guessed at. The field is the only
    /// thing that can tell us this, and reading a shape we do not understand is how a workout
    /// gets scored wrongly rather than not at all.
    func testARecordFromANewerSchemaIsRefused() throws {
        let encoded = try WireCodec.encode(record(engineMidSession(), savedAt: t0))
        let bumped = try JSONSerialization.data(
            withJSONObject: replacing("schema", with: SessionRecord.schema + 1,
                                      in: try JSONSerialization.jsonObject(with: encoded))
        )

        XCTAssertThrowsError(try WireCodec.decode(SessionRecord.self, from: bumped))
    }

    /// A truncated or mangled file yields **nothing**, never a partial session. The caller falls
    /// back to the plan list, which is a worse screen than a resumed runner and a far better one
    /// than a runner driving an engine that cannot mean anything.
    func testARecordThatCannotBeDecodedIsRefusedRatherThanHalfApplied() {
        let mangled = Data(#"{"planName":"Upper Body A","currentIndex":3"#.utf8)

        XCTAssertThrowsError(try WireCodec.decode(SessionRecord.self, from: mangled))
    }

    /// `Interval`'s tolerance is inherited: the record carries intervals, so a record holding one
    /// written before `intensity` existed must still load.
    func testAnIntervalInARecordWithNoIntensityStillDecodes() throws {
        let encoded = try WireCodec.encode(record(engineMidSession(count: 1), savedAt: t0))
        let stripped = try JSONSerialization.data(
            withJSONObject: removing("intensity", from: try JSONSerialization.jsonObject(with: encoded))
        )

        let back = try WireCodec.decode(SessionRecord.self, from: stripped)

        XCTAssertNil(back.intervals.first?.intensity)
        XCTAssertEqual(back.intervals.first?.name, "Work 0", "the rest of the interval survives")
    }

    // MARK: - Restoring, and what is refused

    /// A record with no intervals can only arrive from a file, never from an engine — so this
    /// goes through JSON, which is also where a record this broken would actually come from.
    func testRestoringRefusesAnEmptyIntervalList() throws {
        let encoded = try WireCodec.encode(record(engineMidSession(count: 1), savedAt: t0))
        let emptied = try JSONSerialization.data(
            withJSONObject: replacing("intervals", with: [Any](),
                                      in: try JSONSerialization.jsonObject(with: encoded))
        )

        XCTAssertNil(ExecutionEngine(restoring: try WireCodec.decode(SessionRecord.self, from: emptied)))
    }

    func testRestoringRefusesASessionThatNeverStarted() {
        let idle = ExecutionEngine(intervals: [timed(0, 60)])

        XCTAssertNil(ExecutionEngine(restoring: record(idle)))
    }

    /// An index past the end of the plan would drive the whole screen from `nil` and record
    /// nonsense into history.
    func testRestoringRefusesAnIndexPastTheEndOfThePlan() throws {
        let encoded = try WireCodec.encode(record(engineMidSession(count: 2), savedAt: t0))
        let bumped = try JSONSerialization.data(
            withJSONObject: replacing("currentIndex", with: 99,
                                      in: try JSONSerialization.jsonObject(with: encoded))
        )

        XCTAssertNil(ExecutionEngine(restoring: try WireCodec.decode(SessionRecord.self, from: bumped)))
    }

    /// An outcome filed against an interval that does not exist means the record and its own
    /// interval list disagree. There is no way to tell which half is right, so neither is used.
    func testRestoringRefusesAnOutcomeForAnIntervalThatDoesNotExist() throws {
        let encoded = try WireCodec.encode(record(engineMidSession(count: 2), savedAt: t0))
        let mutated = try JSONSerialization.data(
            withJSONObject: addingOutcome(forIndex: 99, to: try JSONSerialization.jsonObject(with: encoded))
        )

        XCTAssertNil(ExecutionEngine(restoring: try WireCodec.decode(SessionRecord.self, from: mutated)))
    }

    // MARK: - Restoring, and what survives

    /// A record saved while **paused** resumes paused with the clock still held — and the gap
    /// between the pause and the restore is **not** counted as exercise.
    ///
    /// This is the case the record carries `pausedAt` for. Measuring the pause from the restore
    /// instead would make ten minutes of a dead phone look like ten minutes of work, and that
    /// number goes into `totalDuration` and then into history, where it is permanent.
    func testARestoredPausedSessionHoldsItsClock() {
        var engine = engineMidSession()
        _ = engine.advance(at: t0.addingTimeInterval(30))
        _ = engine.pause(at: t0.addingTimeInterval(30))
        let saved = record(engine, savedAt: t0.addingTimeInterval(30))

        let resumed = ExecutionEngine(restoring: saved)

        XCTAssertEqual(resumed?.phase, .paused)
        XCTAssertEqual(resumed?.remaining(at: t0.addingTimeInterval(600)), 60,
                       "the clock is still held, at the value it was held at")
        XCTAssertEqual(resumed?.elapsed(at: t0.addingTimeInterval(600)), 30,
                       "the nine and a half minutes spent dead are not time spent exercising")
    }

    /// And resuming afterwards continues to leave the gap out, rather than only looking right
    /// while nobody has touched it.
    func testAPauseSpanningARestoreIsExcludedFromTheTotal() {
        var engine = engineMidSession()
        _ = engine.advance(at: t0.addingTimeInterval(30))
        _ = engine.pause(at: t0.addingTimeInterval(30))
        let saved = record(engine, savedAt: t0.addingTimeInterval(30))

        var resumed = try? XCTUnwrap(ExecutionEngine(restoring: saved))
        _ = resumed?.resume(at: t0.addingTimeInterval(600))

        XCTAssertEqual(resumed?.elapsed(at: t0.addingTimeInterval(660)), 90,
                       "30 seconds before the pause, plus 60 after the resume")
    }

    /// A record anchored minutes back is brought up to date in **one** step, because it goes
    /// through `ExecutionEngine` rather than re-deriving the position. This is the property that
    /// makes it safe to answer the watch from a stale file: the projection from a stale anchor
    /// and from a fresh one agree, so a recovery can never rewind the wrist.
    func testARestoredRunningSessionCatchesUpInOneTick() throws {
        var engine = engineMidSession()
        _ = engine.advance(at: t0.addingTimeInterval(60))
        let saved = record(engine)

        // The engine, restored and ticked, emits exactly one event for three elapsed intervals.
        var restored = try XCTUnwrap(ExecutionEngine(restoring: saved))
        let events = restored.tick(now: t0.addingTimeInterval(200))
        XCTAssertEqual(events, [.advanced(from: 1, to: 3)], "three intervals elapsed, one event")

        // And the record lands in the same place without anyone having to know that.
        let advanced = try XCTUnwrap(saved.advanced(to: t0.addingTimeInterval(200)))
        XCTAssertEqual(advanced.currentIndex, 3)
        XCTAssertEqual(advanced.intervalEnd, t0.addingTimeInterval(240))
    }

    /// A crash does not lose the sets already scored. This is the whole reason the record carries
    /// `outcomes` rather than just a position.
    func testARestoredRecordKeepsTheOutcomesItHadAlreadyRecorded() throws {
        var engine = engineMidSession()
        _ = engine.advance(at: t0.addingTimeInterval(60))

        let restored = try XCTUnwrap(ExecutionEngine(restoring: record(engine)))

        XCTAssertEqual(restored.outcomes[0]?.status, .completed, "the first interval was finished")
        XCTAssertEqual(restored.outcomes[3]?.status, .pending, "and the fourth was not")
    }

    // MARK: - Which records count

    /// The age window is the only thing bounding a **rep** record, which unlike a timed one
    /// cannot self-terminate on restore: a rep interval has no length, so nothing moves it on and
    /// it would wait for a tap forever.
    func testASessionOlderThanTheWindowIsNotLive() {
        let stale = record(engineMidSession(), savedAt: t0)

        XCTAssertTrue(stale.isLive(at: t0.addingTimeInterval(SessionRecord.maximumAge - 1)))
        XCTAssertFalse(stale.isLive(at: t0.addingTimeInterval(SessionRecord.maximumAge + 1)))
    }

    /// A finished session is **not live** — nothing should resume it — but it is still worth
    /// telling the watch about, because the `DONE` screen is drawn from it. Answering
    /// `.sessionEnded` there would erase the one thing the wrist has to show.
    func testAFinishedRecordIsAnswerableButNotLive() throws {
        var engine = engineMidSession(count: 1)
        _ = engine.advance(at: t0.addingTimeInterval(60))
        let finished = record(engine, savedAt: t0)
        XCTAssertEqual(finished.phase, .finished, "the fixture really did finish")

        XCTAssertFalse(finished.isLive(at: t0))
        XCTAssertTrue(finished.isPresentable(at: t0))

        // The clock has not moved, so the same argument applies to the watch's projection.
        XCTAssertTrue(finished.isPresentable(at: t0.addingTimeInterval(SessionRecord.maximumAge - 1)))
        XCTAssertFalse(finished.isPresentable(at: t0.addingTimeInterval(SessionRecord.maximumAge + 1)))
    }

    /// A rep session is live — it is waiting for a tap, which is not the same as being over.
    func testARepSessionIsLive() {
        var engine = ExecutionEngine(intervals: [rep(0), rep(1)])
        _ = engine.start(at: t0)

        XCTAssertTrue(record(engine).isLive(at: t0))
    }

    // MARK: - The record and the wire cannot disagree

    /// The phone writes the record and the application-context snapshot from the same engine at
    /// the same moment, so they are the same intervals out of the same state. Asserted because
    /// "the two halves of the app disagree about what is happening" is the failure this project
    /// has paid for five times over.
    func testARecordWrittenAtTheSameInstantAsASnapshotSaysTheSameThing() {
        var engine = engineMidSession()
        _ = engine.advance(at: t0.addingTimeInterval(60))
        let saved = record(engine)

        let snapshot = saved.snapshot

        XCTAssertEqual(snapshot.intervals, engine.intervals)
        XCTAssertEqual(snapshot.startedAt, engine.startedAt)
        XCTAssertEqual(snapshot.state.currentIndex, engine.currentIndex)
        XCTAssertEqual(snapshot.state.intervalEnd, engine.intervalEnd)
        XCTAssertEqual(snapshot.state.isPaused, engine.phase == .paused)
        XCTAssertEqual(snapshot.state.isFinished, engine.phase == .finished)
    }

    // MARK: - JSON surgery

    private func removing(_ key: String, from value: Any) -> Any {
        if var object = value as? [String: Any] {
            object.removeValue(forKey: key)
            return object.mapValues { removing(key, from: $0) }
        }
        if let array = value as? [Any] {
            return array.map { removing(key, from: $0) }
        }
        return value
    }

    private func replacing(_ key: String, with newValue: Any, in value: Any) -> Any {
        if var object = value as? [String: Any] {
            if object[key] != nil { object[key] = newValue }
            return object.mapValues { replacing(key, with: newValue, in: $0) }
        }
        if let array = value as? [Any] {
            return array.map { replacing(key, with: newValue, in: $0) }
        }
        return value
    }

    /// Files an outcome against an index no interval has.
    ///
    /// `JSONEncoder` writes `[Int: IntervalOutcome]` as a JSON **object with stringified integer
    /// keys** (`{"0":{…},"1":{…}}`), not as an array of pairs — verified by encoding one rather
    /// than assumed, because the fixture has to edit the shape that is really on disk.
    private func addingOutcome(forIndex index: Int, to value: Any) -> Any {
        guard var object = value as? [String: Any], var outcomes = object["outcomes"] as? [String: Any] else {
            return value
        }
        outcomes[String(index)] = ["status": "completed"]
        object["outcomes"] = outcomes
        return object
    }
}
