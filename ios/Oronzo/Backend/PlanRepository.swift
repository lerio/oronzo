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
}

private struct ExerciseRow: Decodable {
    let id: UUID
    let name: String
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
                                    exerciseID: step.exercise_id,
                                    label: step.label,
                                    sets: max(1, step.sets),
                                    mode: StepMode(rawValue: step.mode ?? "reps") ?? .reps,
                                    duration: step.duration_seconds.map(TimeInterval.init),
                                    reps: step.reps,
                                    targetWeightKg: step.target_weight_kg,
                                    restAfter: step.rest_after_seconds.map(TimeInterval.init)
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
        + "target_weight_kg,rest_after_seconds))"

    func fetchPlans() async throws -> [Plan] {
        let rows: [PlanRow] = try await Backend.client
            .from("plans")
            .select(Self.planSelect)
            .order("updated_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toDomain() }
    }

    func fetchExerciseNames() async throws -> [UUID: String] {
        let rows: [ExerciseRow] = try await Backend.client
            .from("exercises")
            .select("id,name")
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.name) })
    }
}
