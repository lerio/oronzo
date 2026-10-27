import XCTest
@testable import OronzoCore

/// The weekday and preferred-time rules both clients share.
///
/// A weekday that is off by one is invisible until the wrong workout is on the wrist, and a
/// preferred-time order that differs between the builder and the phone is invisible until the
/// user compares two screens. Both are pure functions; these tests are the only cheap place to
/// catch either.
final class WeekScheduleTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func workout(
        _ name: String,
        at time: String? = nil,
        id: UUID = UUID()
    ) -> Workout {
        Workout(id: id, name: name, preferredTime: time.flatMap { PreferredTime(postgres: $0) })
    }

    // MARK: - ISO weekdays

    func testSundayIsSevenAndMondayIsOne() {
        // 25 October 2026 is a Sunday; the next day is a Monday.
        XCTAssertEqual(WeekSchedule.isoWeekday(of: date(2026, 10, 25), calendar: calendar), .sunday)
        XCTAssertEqual(WeekSchedule.isoWeekday(of: date(2026, 10, 26), calendar: calendar), .monday)
    }

    func testEveryCalendarDayMapsToTheMatchingISOWeekday() {
        let expected: [Weekday] = [
            .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
        ]
        for (offset, weekday) in expected.enumerated() {
            let day = calendar.date(byAdding: .day, value: offset, to: date(2026, 10, 25))!
            XCTAssertEqual(WeekSchedule.isoWeekday(of: day, calendar: calendar), weekday)
        }
    }

    // MARK: - A day's workouts

    func testWorkoutsAreOrderedByTimeThenNameThenID() {
        let anytime = workout("Anytime")
        let evening = workout("Evening", at: "18:00")
        let morningB = workout("Morning B", at: "07:00")
        let morningA = workout("Morning A", at: "07:00")

        let plan = WeekPlan(name: "My week", slots: [
            PlanSlot(workoutID: anytime.id, weekday: .monday),
            PlanSlot(workoutID: evening.id, weekday: .monday),
            PlanSlot(workoutID: morningB.id, weekday: .monday),
            PlanSlot(workoutID: morningA.id, weekday: .monday),
        ])

        let result = WeekSchedule.workouts(
            on: .monday,
            in: plan,
            from: [anytime, evening, morningB, morningA]
        )

        XCTAssertEqual(result.map(\.name), ["Morning A", "Morning B", "Evening", "Anytime"])
    }

    func testNamesAreComparedCaseInsensitively() {
        let upper = workout("alpha", at: "07:00")
        let lower = workout("Beta", at: "07:00")
        let plan = WeekPlan(name: "P", slots: [
            PlanSlot(workoutID: upper.id, weekday: .monday),
            PlanSlot(workoutID: lower.id, weekday: .monday),
        ])

        XCTAssertEqual(
            WeekSchedule.workouts(on: .monday, in: plan, from: [lower, upper]).map(\.name),
            ["alpha", "Beta"]
        )
    }

    func testTheSameWorkoutCanAppearOnTwoDays() {
        let push = workout("Push", at: "07:00")
        let plan = WeekPlan(name: "P", slots: [
            PlanSlot(workoutID: push.id, weekday: .monday),
            PlanSlot(workoutID: push.id, weekday: .thursday),
        ])

        XCTAssertEqual(WeekSchedule.workouts(on: .monday, in: plan, from: [push]).map(\.name), ["Push"])
        XCTAssertEqual(WeekSchedule.workouts(on: .thursday, in: plan, from: [push]).map(\.name), ["Push"])
        XCTAssertTrue(WeekSchedule.workouts(on: .tuesday, in: plan, from: [push]).isEmpty)
    }

    func testSlotsWhoseWorkoutIsMissingAreSkipped() {
        let present = workout("Push")
        let plan = WeekPlan(name: "P", slots: [
            PlanSlot(workoutID: present.id, weekday: .monday),
            PlanSlot(workoutID: UUID(), weekday: .monday),
        ])

        XCTAssertEqual(
            WeekSchedule.workouts(on: .monday, in: plan, from: [present]).map(\.name),
            ["Push"]
        )
    }

    func testEqualNamesAndTimesFallBackToTheID() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertTrue(WeekSchedule.precedes(workout("Same", at: "07:00", id: first),
                                            workout("Same", at: "07:00", id: second)))
        XCTAssertFalse(WeekSchedule.precedes(workout("Same", at: "07:00", id: second),
                                             workout("Same", at: "07:00", id: first)))
    }

    // MARK: - PreferredTime

    func testPreferredTimeParsesPostgresAndBuilderForms() {
        XCTAssertEqual(PreferredTime(postgres: "07:00:00")?.display, "07:00")
        XCTAssertEqual(PreferredTime(postgres: "18:05")?.display, "18:05")
        XCTAssertEqual(PreferredTime(postgres: "7:05")?.display, "07:05")
    }

    func testPreferredTimeRejectsMalformedValues() {
        XCTAssertNil(PreferredTime(postgres: ""))
        XCTAssertNil(PreferredTime(postgres: "24:00"))
        XCTAssertNil(PreferredTime(postgres: "07:60"))
        XCTAssertNil(PreferredTime(postgres: "nope"))
        XCTAssertNil(PreferredTime(postgres: "07"))
    }

    func testPreferredTimeSortsByHourThenMinute() {
        let early = PreferredTime(hour: 7, minute: 30)
        let late = PreferredTime(hour: 18, minute: 0)
        XCTAssertLessThan(early, late)
        XCTAssertEqual(early.display, "07:30")
    }

    // MARK: - Workout cache compatibility

    func testAWorkoutWithoutPreferredTimeStillDecodes() throws {
        let payload = """
        {"id":"00000000-0000-0000-0000-00000000ABCD","name":"Push","blocks":[]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Workout.self, from: payload)
        XCTAssertNil(decoded.preferredTime)
        XCTAssertEqual(decoded.name, "Push")
    }

    func testAnUnsetPreferredTimeIsOmittedWhenEncoded() throws {
        let encoded = try JSONEncoder().encode(workout("Push"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["preferredTime"])
    }
}
