import Foundation

/// ISO weekday: **1 = Monday … 7 = Sunday**. The database, the builder and the phone all use
/// this numbering; the only place it is converted is `WeekSchedule.isoWeekday(of:calendar:)`,
/// because `Calendar` numbers Sunday as 1.
public enum Weekday: Int, Codable, CaseIterable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7
}

/// One workout scheduled on one weekday. The triple `(plan, workout, weekday)` is the identity;
/// the same workout may appear on several days and in several plans.
public struct PlanSlot: Codable, Equatable, Hashable, Sendable {
    public let workoutID: UUID
    public let weekday: Weekday

    public init(workoutID: UUID, weekday: Weekday) {
        self.workoutID = workoutID
        self.weekday = weekday
    }
}

/// A weekly template. No dates, no start or end: it repeats until the user changes it.
public struct WeekPlan: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let slots: [PlanSlot]

    public init(id: UUID = UUID(), name: String, slots: [PlanSlot] = []) {
        self.id = id
        self.name = name
        self.slots = slots
    }
}
