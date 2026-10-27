import Foundation

/// Which workouts belong to a day, in the order both surfaces must show them.
///
/// This is a pure function on purpose: the phone's Today screen, the All Workouts list and the
/// tests all need the same answer, and a weekday that is off by one is invisible until the wrong
/// workout is on the wrist. The one conversion from `Calendar` lives here.
public enum WeekSchedule {

    /// `Calendar` numbers Sunday as 1 and Monday as 2; ISO numbers Monday as 1 and Sunday as 7.
    public static func isoWeekday(of date: Date, calendar: Calendar = .current) -> Weekday {
        let value = ((calendar.component(.weekday, from: date) + 5) % 7) + 1
        return Weekday(rawValue: value) ?? .monday
    }

    /// The workouts scheduled on `weekday`, in preferred-time order.
    ///
    /// Slots that point at a workout missing from `workouts` are skipped rather than surfaced as
    /// an error: a plan can be fresher than the workout list during a refresh, and one missing
    /// row must not take the day down.
    public static func workouts(
        on weekday: Weekday,
        in plan: WeekPlan,
        from workouts: [Workout]
    ) -> [Workout] {
        let byID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return plan.slots
            .filter { $0.weekday == weekday }
            .compactMap { byID[$0.workoutID] }
            .sorted(by: precedes)
    }

    /// Preferred time ascending (nil last), then name case-insensitively, then id.
    ///
    /// The builder uses the identical rule. Two orderings would put different workouts first on
    /// the two surfaces for the same plan, which is exactly the drift `WorkoutFlattener` exists
    /// to prevent on the interval stream.
    public static func precedes(_ lhs: Workout, _ rhs: Workout) -> Bool {
        switch (lhs.preferredTime, rhs.preferredTime) {
        case let (left?, right?):
            if left != right { return left < right }
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case (nil, nil):
            break
        }

        let leftName = lhs.name.lowercased()
        let rightName = rhs.name.lowercased()
        if leftName != rightName { return leftName < rightName }
        // `UUID.uuidString` is uppercase; Postgres ids are lowercase. Compare lowercase so the
        // web comparator (`compareWorkoutsByTimeThenName`) agrees on the final tiebreak.
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }
}
