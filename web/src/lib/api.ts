import { supabase } from './supabase';
import type { Exercise, Plan, PlanBlock, PlanStep, StepMode } from './types';

/** Kept on one line: PostgREST parses this as a query string, and embedded newlines break it. */
const PLAN_SELECT =
  'id,name,updated_at,plan_blocks(id,position,name,rounds,rest_between_rounds_seconds,' +
  'plan_steps(id,position,exercise_id,label,sets,mode,duration_seconds,reps,' +
  'target_weight_kg,rest_after_seconds,intensity))';

type PlanRow = {
  id: string;
  name: string;
  updated_at: string;
  plan_blocks: (Omit<PlanBlock, 'steps'> & { plan_steps: PlanStep[] })[];
};

function toPlan(row: PlanRow): Plan {
  return {
    id: row.id,
    name: row.name,
    updated_at: row.updated_at,
    blocks: [...(row.plan_blocks ?? [])]
      .sort((a, b) => a.position - b.position)
      .map((block) => ({
        ...block,
        steps: [...(block.plan_steps ?? [])].sort((a, b) => a.position - b.position),
      })),
  };
}

export async function listPlans(): Promise<Plan[]> {
  const { data, error } = await supabase.from('plans').select(PLAN_SELECT).order('updated_at', { ascending: false });
  if (error) throw error;
  return (data as unknown as PlanRow[]).map(toPlan);
}

export async function getPlan(id: string): Promise<Plan | null> {
  const { data, error } = await supabase.from('plans').select(PLAN_SELECT).eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toPlan(data as unknown as PlanRow) : null;
}

/**
 * Saves the whole plan in one transaction. A plan save touches 1 + N + M rows, so doing it
 * as sequential client calls risks a half-saved plan if one fails.
 */
export async function savePlan(plan: Plan): Promise<string> {
  const payload = {
    id: plan.id || null,
    name: plan.name,
    blocks: plan.blocks.map((block, blockIndex) => ({
      name: block.name,
      rounds: block.rounds,
      rest_between_rounds_seconds: block.rest_between_rounds_seconds,
      steps: block.steps.map((step, stepIndex) => ({
        exercise_id: step.exercise_id,
        label: step.label,
        sets: step.sets,
        mode: step.mode,
        duration_seconds: step.duration_seconds,
        reps: step.reps,
        target_weight_kg: step.target_weight_kg,
        rest_after_seconds: step.rest_after_seconds,
        intensity: step.intensity,
        position: stepIndex,
      })),
      position: blockIndex,
    })),
  };

  const { data, error } = await supabase.rpc('save_plan', { payload });
  if (error) throw error;
  return data as string;
}

export async function deletePlan(id: string): Promise<void> {
  const { error } = await supabase.from('plans').delete().eq('id', id);
  if (error) throw error;
}

export async function listExercises(): Promise<Exercise[]> {
  const { data, error } = await supabase
    .from('exercises')
    .select('*')
    .order('muscle_group', { ascending: true })
    .order('name', { ascending: true });
  if (error) throw error;
  return data as Exercise[];
}

/**
 * Creates one of the user's own exercises.
 *
 * Takes only what a person chooses. The per-mode defaults are filled in here, beside the
 * constraint that makes them necessary — `exercises_mode_shape` rejects a timed exercise with no
 * duration, and the plan editor pre-fills a new step from all of them. Two forms create
 * exercises now (the Exercises page and the plan editor's picker), so this is the one place that
 * decides what a new one looks like.
 *
 * `has_two_sides` is sent explicitly rather than left to the column's default: it is the one
 * thing here a checkbox decides. Note this needs `0012` applied — an insert naming a column the
 * database does not have is a `400`, unlike the reads, which tolerate new columns.
 */
export async function createExercise(input: {
  name: string;
  muscle_group: string;
  default_mode: StepMode;
  has_two_sides: boolean;
}): Promise<Exercise> {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;

  const { data, error } = await supabase
    .from('exercises')
    .insert({
      ...input,
      user_id: userData.user.id,
      slug: null,
      default_duration_seconds: input.default_mode === 'time' ? 45 : null,
      default_reps: input.default_mode === 'reps' ? 10 : null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return data as Exercise;
}

export async function deleteExercise(id: string): Promise<void> {
  const { error } = await supabase.from('exercises').delete().eq('id', id);
  if (error) throw error;
}

export type SessionSummary = {
  id: string;
  plan_name: string;
  started_at: string;
  finished_at: string | null;
  status: string;
  total_duration_seconds: number | null;
  step_count: number;
};

export async function listSessions(limit = 100): Promise<SessionSummary[]> {
  const { data, error } = await supabase
    .from('sessions')
    .select('id,plan_name,started_at,finished_at,status,total_duration_seconds,session_steps(count)')
    .order('started_at', { ascending: false })
    .limit(limit);
  if (error) throw error;

  return (data as unknown as (Omit<SessionSummary, 'step_count'> & { session_steps: { count: number }[] })[]).map(
    (row) => ({
      id: row.id,
      plan_name: row.plan_name,
      started_at: row.started_at,
      finished_at: row.finished_at,
      status: row.status,
      total_duration_seconds: row.total_duration_seconds,
      step_count: row.session_steps?.[0]?.count ?? 0,
    }),
  );
}

/**
 * Deletes a session. Its `session_steps` go with it: that FK is ON DELETE CASCADE, and both
 * tables carry owner-scoped `for all` policies, so nothing else has to be deleted by hand.
 */
export async function deleteSession(id: string): Promise<void> {
  const { error } = await supabase.from('sessions').delete().eq('id', id);
  if (error) throw error;
}
