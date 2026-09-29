import Foundation
import OronzoCore
import Supabase

// MARK: - Wire types
//
// These deliberately mirror the PostgREST payload — snake_case property names and all —
// so that decoding needs no CodingKeys and cannot silently drift from the schema. They are
// mapped to OronzoCore domain types immediately and never escape this file.

private struct PlanRow: Decodable {
    let id: UUID
    let name: String
    let plan_blocks: [BlockRow]?
}

private struct BlockRow: Decodable {
    let id: UUID
    let position: Int
    let name: String?
    let rounds: Int
    let rest_between_rounds_seconds: Int?
    let plan_steps: [StepRow]?
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
    /// rather than failing the whole step, because a plan that will not load is worse than a plan
    /// whose effort is missing.
    let intensity: String?
    /// Optional for the same reason every column on this row is: an older database — or a
    /// response that predates `0014` — must still decode.
    let prepare_seconds: Int?
}

private struct ExerciseRow: Decodable {
    let id: UUID
    let name: String
    let has_two_sides: Bool
}

/// The `plan_steps` columns a load adjustment writes, as a PATCH body.
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

/// A plan write that did not happen.
enum PlanWriteError: LocalizedError {

    /// The step was not there to update — either the id is stale, or RLS refused the row.
    ///
    /// **Both look identical from here, and both are silent without this case.** PostgREST answers
    /// a PATCH that matched nothing with `200` and an empty array, so without checking the response
    /// the app would report success over a change that went nowhere. The likeliest cause by far is
    /// `save_plan`'s whole-tree replace: it mints new step ids, so a plan edited on the web while a
    /// session is running leaves the phone holding an id that no longer exists.
    case stepNotFound

    var errorDescription: String? {
        switch self {
        case .stepNotFound:
            "this plan changed elsewhere, so there was nothing to update"
        }
    }
}

// MARK: - Mapping

private extension PlanRow {
    func toDomain() -> Plan {
        Plan(
            id: id,
            name: name,
            blocks: (plan_blocks ?? [])
                .sorted { $0.position < $1.position }
                .map { block in
                    PlanBlock(
                        name: block.name,
                        rounds: max(1, block.rounds),
                        restBetweenRounds: block.rest_between_rounds_seconds.map(TimeInterval.init),
                        steps: (block.plan_steps ?? [])
                            .sorted { $0.position < $1.position }
                            .map { step in
                                PlanStep(
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

// MARK: - Repository

struct PlanRepository: Sendable {

    /// One line on purpose: PostgREST parses this as a query string, so embedded newlines
    /// or stray whitespace break it.
    private static let planSelect =
        "id,name,plan_blocks(id,position,name,rounds,rest_between_rounds_seconds,"
        + "plan_steps(id,position,exercise_id,label,sets,mode,duration_seconds,reps,"
        + "target_weight_kg,rest_after_seconds,intensity,prepare_seconds))"

    func fetchPlans() async throws -> [Plan] {
        let rows: [PlanRow] = try await Backend.client
            .from("plans")
            .select(Self.planSelect)
            // The order the user arranged the list in on the web, not when it was last edited.
            // `position` is deliberately absent from `planSelect`: PostgREST applies `order`
            // independently of the select list, and leaving it out keeps `PlanRow` — and the
            // unversioned `PlanCache` file written from it — byte-for-byte what it was.
            .order("position", ascending: true)
            .execute()
            .value
        return rows.map { $0.toDomain() }
    }

    /// Kept on one line: PostgREST parses this as a query string, and embedded newlines break it.
    /// A column named here that the database does not have is a runtime `400` on a device, not a
    /// compile error — `has_two_sides` arrives with `0012`.
    func fetchExercises() async throws -> [UUID: ExerciseInfo] {
        let rows: [ExerciseRow] = try await Backend.client
            .from("exercises")
            .select("id,name,has_two_sides")
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map {
            ($0.id, ExerciseInfo(name: $0.name, hasTwoSides: $0.has_two_sides))
        })
    }

    /// Writes one step's load — the runner's Adjust button, and the only **write** this type has.
    ///
    /// **Narrow on purpose.** The alternative is `save_plan`, which is the only other way a step's
    /// load can change and is the wrong tool twice over: it replaces the whole tree, so it mints
    /// new block and step ids (invalidating the very id this session is holding, and any other
    /// session's), and it would write back a plan the web builder may have changed since this
    /// session started. One row, two columns, the values the user chose.
    ///
    /// It needs no new SQL: `plan_steps` carries a `for all` RLS policy resolving ownership through
    /// `plan_blocks → plans.user_id`, and the `update` grant on it, both from `0001`. The two CHECK
    /// constraints that still apply are the ones the caller already respects — a weight at or above
    /// zero (`LoadDial` floors there) and one of the three effort words.
    ///
    /// A load is not a receipt. Retrying this is safe, unlike the history insert — it writes an
    /// absolute value rather than appending a row — so `SessionController` retries once through a
    /// renewed session, the way `PlanStore.refresh` does.
    func updateStepLoad(stepID: UUID, weightKg: Double?, intensity: Intensity?) async throws {
        let patched: [PatchedStep] = try await Backend.client
            .from("plan_steps")
            .update(StepLoadPatch(
                target_weight_kg: weightKg,
                // The three words are the same three in all three languages, so no mapping.
                intensity: intensity?.rawValue
            ))
            .eq("id", value: stepID)
            .select("id")
            .execute()
            .value

        // **An empty echo is a failure, not a success.** See `PlanWriteError.stepNotFound`.
        guard !patched.isEmpty else { throw PlanWriteError.stepNotFound }
    }
}
