import { supabase } from './supabase';
import type { Exercise, Plan, PlanBlock, PlanStep, StepMode } from './types';

/** Kept on one line: PostgREST parses this as a query string, and embedded newlines break it. */
const PLAN_SELECT =
  'id,name,notes,updated_at,plan_blocks(id,position,name,rounds,rest_between_rounds_seconds,' +
  'plan_steps(id,position,kind,exercise_id,label,mode,duration_seconds,reps,target_weight_kg,rest_after_seconds,notes))';

type PlanRow = {
  id: string;
  name: string;
  notes: string | null;
  updated_at: string;
  plan_blocks: (Omit<PlanBlock, 'steps'> & { plan_steps: PlanStep[] })[];
};

function toPlan(row: PlanRow): Plan {
  return {
    id: row.id,
    name: row.name,
    notes: row.notes,
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
    notes: plan.notes,
    blocks: plan.blocks.map((block, blockIndex) => ({
      name: block.name,
      rounds: block.rounds,
      rest_between_rounds_seconds: block.rest_between_rounds_seconds,
      steps: block.steps.map((step, stepIndex) => ({
        kind: step.kind,
        exercise_id: step.exercise_id,
        label: step.label,
        mode: step.mode,
        duration_seconds: step.duration_seconds,
        reps: step.reps,
        target_weight_kg: step.target_weight_kg,
        rest_after_seconds: step.rest_after_seconds,
        notes: step.notes,
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

export async function createExercise(input: {
  name: string;
  muscle_group: string;
  equipment: string;
  default_mode: StepMode;
  default_duration_seconds: number | null;
  default_reps: number | null;
}): Promise<Exercise> {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;

  const { data, error } = await supabase
    .from('exercises')
    .insert({ ...input, user_id: userData.user.id, slug: null })
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
