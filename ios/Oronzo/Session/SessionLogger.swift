import Foundation
import OronzoCore
import Supabase

/// Writes a finished session to Supabase.
///
/// Dates go over the wire as explicit ISO-8601 strings rather than relying on the SDK's
/// default date strategy — a mismatch there fails the insert at runtime, which is the worst
/// possible place to discover it.
struct SessionLogger {

    /// Postgres `timestamptz` takes ISO-8601. `Date.ISO8601FormatStyle` rather than
    /// `ISO8601DateFormatter` because the latter is a non-Sendable class, which Swift 6
    /// strict concurrency refuses to hold in a static.
    private static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    // MARK: - Wire types
    //
    // snake_case property names mirror the PostgREST payload, as elsewhere in this project,
    // so decoding and encoding need no CodingKeys and cannot drift from the schema.

    private struct NewSession: Encodable {
        let user_id: UUID
        let plan_id: UUID
        let plan_name: String
        let started_at: String
        let finished_at: String
        let status: String
        let total_duration_seconds: Int
    }

    private struct InsertedSession: Decodable {
        let id: UUID
    }

    private struct NewStep: Encodable {
        let session_id: UUID
        let position: Int
        let set_index: Int
        let block_round: Int
        let block_name: String?
        let kind: String
        let exercise_id: UUID?
        let exercise_name: String
        let planned_mode: String?
        let planned_duration_seconds: Int?
        let planned_reps: Int?
        let planned_weight_kg: Double?
        let actual_duration_seconds: Int?
        let actual_reps: Int?
        let actual_weight_kg: Double?
        let status: String
    }

    /// Records the session and its steps. Returns the new session's id.
    @discardableResult
    func log(_ session: CompletedSession, planID: UUID, planName: String) async throws -> UUID {
        let userID = try await Backend.client.auth.session.user.id

        // The parent row first: the steps need its id, and a session without steps is still
        // a truthful record of having trained.
        let inserted: InsertedSession = try await Backend.client
            .from("sessions")
            .insert(
                NewSession(
                    user_id: userID,
                    plan_id: planID,
                    plan_name: planName,
                    started_at: session.startedAt.formatted(Self.iso),
                    finished_at: session.finishedAt.formatted(Self.iso),
                    status: session.status.rawValue,
                    total_duration_seconds: Int(session.totalDuration.rounded())
                )
            )
            .select("id")
            .single()
            .execute()
            .value

        let rows = session.steps.map { step in
            NewStep(
                session_id: inserted.id,
                position: step.position,
                set_index: step.setIndex,
                block_round: step.blockRound,
                block_name: step.blockName,
                kind: step.kind.rawValue,
                exercise_id: step.exerciseID,
                exercise_name: step.exerciseName,
                planned_mode: step.plannedMode?.rawValue,
                planned_duration_seconds: step.plannedDuration.map { Int($0.rounded()) },
                planned_reps: step.plannedReps,
                planned_weight_kg: step.plannedWeightKg,
                actual_duration_seconds: step.actualDuration.map { Int($0.rounded()) },
                actual_reps: step.actualReps,
                actual_weight_kg: step.actualWeightKg,
                status: step.status.rawValue
            )
        }

        if !rows.isEmpty {
            try await Backend.client.from("session_steps").insert(rows).execute()
        }

        return inserted.id
    }
}
