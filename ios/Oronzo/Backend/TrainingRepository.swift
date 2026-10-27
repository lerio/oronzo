import Foundation
import OronzoCore
import Supabase

// MARK: - Wire types
//
// These deliberately mirror the PostgREST payload — snake_case property names and all —
// so that decoding needs no CodingKeys and cannot silently drift from the schema. They are
// mapped to OronzoCore domain types immediately and never escape this file.

private struct WorkoutRow: Decodable {
    let id: UUID
    let name: String
    /// PostgREST serialises `time` as `"07:00:00"`; `PreferredTime(postgres:)` accepts both that
    /// and the builder's `"07:00"`. Nil is "Anytime".
    let preferred_time: String?
    let workout_blocks: [BlockRow]?
}

private struct BlockRow: Decodable {
    let id: UUID
    let position: Int
    let name: String?
    let rounds: Int
    let rest_between_rounds_seconds: Int?
    let workout_steps: [StepRow]?
}

private struct StepRow: Decodable {
    let id: UUID
    let position: Int
    let exercise_id: UUID?
    let label: String?
    let sets: Int
    let mode: String?
    let duration_seconds: Int?
    let reps: Int?
    let target_weight_kg: Double?
    let rest_after_seconds: Int?
    /// The three words live in the database's check constraint; an unknown one decodes to nil
    /// rather than failing the whole step, because a workout that will not load is worse than one
    /// whose effort is missing.
    let intensity: String?
    /// Optional for the same reason every column on this row is: an older database — or a
    /// response that predates `0014` — must still decode.
    let prepare_seconds: Int?
}

private struct WeekPlanRow: Decodable {
    let id: UUID
    let name: String
    let plan_workouts: [PlanSlotRow]?
}

private struct PlanSlotRow: Decodable {
    let workout_id: UUID
    let weekday: Int
}

private struct ExerciseRow: Decodable {
    let id: UUID
    let name: String
    let has_two_sides: Bool
    /// Non-optional like the flag beside it. Whether it is optional changes nothing about the
    /// failure — a select naming a column the database does not have is a `400` before any
    /// decoding happens — so the control is the ordering in the migration, not tolerance here.
    let alternates_sides: Bool
}

/// The `workout_steps` columns a load adjustment writes, as a PATCH body.
///
/// Both are optional, and a nil one is **omitted from the JSON** rather than sent as `null` — which
/// for PostgREST means "leave this column alone". That is exactly right here: an edit carries the
/// step's whole load, so a step with no effort at all must not have one invented for it.
private struct StepLoadPatch: Encodable {
    let target_weight_kg: Double?
    let intensity: String?
}

/// What a PATCH echoes back. `select("id")` on the update, so a non-empty answer *is* the proof
/// that a row was written — see `updateStepLoad`.
private struct PatchedStep: Decodable {
    let id: UUID
}

/// A workout write that did not happen.
enum WorkoutWriteError: LocalizedError {

    /// The step was not there to update — either the id is stale, or RLS refused the row.
    ///
    /// **Both look identical from here, and both are silent without this case.** PostgREST answers
    /// a PATCH that matched nothing with `200` and an empty array, so without checking the response
    /// the app would report success over a change that went nowhere. The likeliest cause by far is
    /// `save_workout`'s whole-tree replace: it mints new step ids, so a workout edited on the web
    /// while a session is running leaves the phone holding an id that no longer exists.
    case stepNotFound

    var errorDescription: String? {
        switch self {
        case .stepNotFound:
            "this workout changed elsewhere, so there was nothing to update"
        }
    }
}

// MARK: - Mapping

private extension WorkoutRow {
    func toDomain() -> Workout {
        Workout(
            id: id,
            name: name,
            preferredTime: preferred_time.flatMap(PreferredTime.init(postgres:)),
            blocks: (workout_blocks ?? [])
                .sorted { $0.position < $1.position }
                .map { block in
                    WorkoutBlock(
                        name: block.name,
                        rounds: max(1, block.rounds),
                        restBetweenRounds: block.rest_between_rounds_seconds.map(TimeInterval.init),
                        steps: (block.workout_steps ?? [])
                            .sorted { $0.position < $1.position }
                            .map { step in
                                WorkoutStep(
                                    id: step.id,
                                    exerciseID: step.exercise_id,
                                    label: step.label,
                                    sets: max(1, step.sets),
                                    mode: StepMode(rawValue: step.mode ?? "reps") ?? .reps,
                                    duration: step.duration_seconds.map(TimeInterval.init),
                                    reps: step.reps,
                                    targetWeightKg: step.target_weight_kg,
                                    restAfter: step.rest_after_seconds.map(TimeInterval.init),
                                    intensity: step.intensity.flatMap(Intensity.init(rawValue:)),
                                    prepareSeconds: step.prepare_seconds.map(TimeInterval.init)
                                )
                            }
                    )
                }
        )
    }
}

private extension WeekPlanRow {
    func toDomain() -> WeekPlan {
        WeekPlan(
            id: id,
            name: name,
            slots: (plan_workouts ?? [])
                .compactMap { slot in
                    guard let weekday = Weekday(rawValue: slot.weekday) else { return nil }
                    return PlanSlot(workoutID: slot.workout_id, weekday: weekday)
                }
                // The web sorts its slots by weekday too; a workout's "Scheduled in" line should
                // read Mon, Thu in the same order on both surfaces.
                .sorted { $0.weekday.rawValue < $1.weekday.rawValue }
        )
    }
}

// MARK: - Repository

struct TrainingRepository: Sendable {

    /// One line on purpose: PostgREST parses this as a query string, so embedded newlines
    /// or stray whitespace break it.
    private static let workoutSelect =
        "id,name,preferred_time,workout_blocks(id,position,name,rounds,rest_between_rounds_seconds,"
        + "workout_steps(id,position,exercise_id,label,sets,mode,duration_seconds,reps,"
        + "target_weight_kg,rest_after_seconds,intensity,prepare_seconds))"

    /// Kept on one line for the same reason.
    private static let weekPlanSelect = "id,name,plan_workouts(workout_id,weekday)"

    func fetchWorkouts() async throws -> [Workout] {
        let rows: [WorkoutRow] = try await Backend.client
            .from("workouts")
            .select(Self.workoutSelect)
            // The order the user arranged the library in on the web, not when it was last edited.
            // `position` is deliberately absent from `workoutSelect`: PostgREST applies `order`
            // independently of the select list, and leaving it out keeps `WorkoutRow` — and the
            // unversioned cache file written from it — byte-for-byte what it was.
            .order("position", ascending: true)
            .execute()
            .value
        return rows.map { $0.toDomain() }
    }

    /// The weekly templates, `created_at` then name. `created_at` is ordered but not selected,
    /// exactly as `position` is above; the plans are few and this keeps the payload small.
    func fetchWeekPlans() async throws -> [WeekPlan] {
        let rows: [WeekPlanRow] = try await Backend.client
            .from("plans")
            .select(Self.weekPlanSelect)
            .order("created_at", ascending: true)
            .order("name", ascending: true)
            .execute()
            .value
        return rows.map { $0.toDomain() }
    }

    /// Kept on one line: PostgREST parses this as a query string, and embedded newlines break it.
    /// A column named here that the database does not have is a runtime `400` on a device, not a
    /// compile error — `has_two_sides` arrives with `0012`, `alternates_sides` with `0016`.
    func fetchExercises() async throws -> [UUID: ExerciseInfo] {
        let rows: [ExerciseRow] = try await Backend.client
            .from("exercises")
            .select("id,name,has_two_sides,alternates_sides")
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map {
            ($0.id, ExerciseInfo(name: $0.name,
                                 hasTwoSides: $0.has_two_sides,
                                 alternatesSides: $0.alternates_sides))
        })
    }

    /// Writes one step's load — the runner's Adjust button, and the only **write** this type has.
    ///
    /// **Narrow on purpose.** The alternative is `save_workout`, which is the only other way a
    /// step's load can change and is the wrong tool twice over: it replaces the whole tree, so it
    /// mints new block and step ids (invalidating the very id this session is holding, and any
    /// other session's), and it would write back a workout the web builder may have changed since
    /// this session started. One row, two columns, the values the user chose.
    ///
    /// It needs no new SQL: `workout_steps` carries a `for all` RLS policy resolving ownership
    /// through `workout_blocks → workouts.user_id`, and the `update` grant on it, both from `0001`.
    /// The two CHECK constraints that still apply are the ones the caller already respects — a
    /// weight at or above zero (`LoadDial` floors there) and one of the three effort words.
    ///
    /// A load is not a receipt. Retrying this is safe, unlike the history insert — it writes an
    /// absolute value rather than appending a row — so `SessionController` retries once through a
    /// renewed session, the way `TrainingStore.refresh` does.
    func updateStepLoad(stepID: UUID, weightKg: Double?, intensity: Intensity?) async throws {
        let patched: [PatchedStep] = try await Backend.client
            .from("workout_steps")
            .update(StepLoadPatch(
                target_weight_kg: weightKg,
                // The three words are the same three in all three languages, so no mapping.
                intensity: intensity?.rawValue
            ))
            .eq("id", value: stepID)
            .select("id")
            .execute()
            .value

        // **An empty echo is a failure, not a success.** See `WorkoutWriteError.stepNotFound`.
        guard !patched.isEmpty else { throw WorkoutWriteError.stepNotFound }
    }
}
