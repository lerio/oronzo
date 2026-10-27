import { supabase } from './supabase';
import { isUniqueViolation } from './errors';
import type {
  Exercise,
  PlanSlot,
  WeekPlan,
  Weekday,
  Workout,
  WorkoutBlock,
  WorkoutStep,
} from './types';

/** Kept on one line: PostgREST parses this as a query string, and embedded newlines break it. */
const WORKOUT_SELECT =
  'id,name,updated_at,preferred_time,workout_blocks(id,position,name,rounds,rest_between_rounds_seconds,' +
  'workout_steps(id,position,exercise_id,label,sets,mode,duration_seconds,reps,' +
  'target_weight_kg,rest_after_seconds,intensity,prepare_seconds))';

/** Kept on one line for the same reason. */
const WEEK_PLAN_SELECT = 'id,name,updated_at,plan_workouts(workout_id,weekday)';

type WorkoutRow = {
  id: string;
  name: string;
  updated_at: string;
  preferred_time: string | null;
  workout_blocks: (Omit<WorkoutBlock, 'steps'> & { workout_steps: WorkoutStep[] })[];
};

function toWorkout(row: WorkoutRow): Workout {
  return {
    id: row.id,
    name: row.name,
    updated_at: row.updated_at,
    // PostgREST serialises `time` as "07:00:00"; the builder and the phone use "07:00".
    preferred_time: row.preferred_time?.slice(0, 5) ?? null,
    blocks: [...(row.workout_blocks ?? [])]
      .sort((a, b) => a.position - b.position)
      .map((block) => ({
        ...block,
        steps: [...(block.workout_steps ?? [])].sort((a, b) => a.position - b.position),
      })),
  };
}

/**
 * The user's workouts, in the order they arranged them.
 *
 * `position` is not in `WORKOUT_SELECT` and does not need to be: PostgREST applies `order` to the
 * outer query independently of the select list, so ordering by a column that is not returned is
 * legal. Keeping it out of the select keeps the payload — and therefore `WorkoutRow`, `Workout`
 * and the iOS cache — unchanged.
 */
export async function listWorkouts(): Promise<Workout[]> {
  const { data, error } = await supabase.from('workouts').select(WORKOUT_SELECT).order('position', { ascending: true });
  if (error) throw error;
  return (data as unknown as WorkoutRow[]).map(toWorkout);
}

export async function getWorkout(id: string): Promise<Workout | null> {
  const { data, error } = await supabase.from('workouts').select(WORKOUT_SELECT).eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toWorkout(data as unknown as WorkoutRow) : null;
}

/**
 * Saves the whole workout in one transaction. A workout save touches 1 + N + M rows, so doing it
 * as sequential client calls risks a half-saved tree if one fails.
 */
export async function saveWorkout(workout: Workout): Promise<string> {
  const payload = {
    id: workout.id || null,
    name: workout.name,
    preferred_time: workout.preferred_time,
    blocks: workout.blocks.map((block, blockIndex) => ({
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
        prepare_seconds: step.prepare_seconds,
        position: stepIndex,
      })),
      position: blockIndex,
    })),
  };

  const { data, error } = await supabase.rpc('save_workout', { payload });
  if (error) throw error;
  return data as string;
}

export async function deleteWorkout(id: string): Promise<void> {
  const { error } = await supabase.from('workouts').delete().eq('id', id);
  if (error) throw error;
}

/**
 * Saves a new order for the workout library. The array **is** the order: index 0 is the top.
 *
 * The ids must be *every* workout the user has — `reorder_workouts` refuses a partial list,
 * because the positions it would leave behind collide. A workout created in another tab since
 * this list was fetched therefore fails here rather than corrupting the order, and the caller
 * reverts to the order it had before the drag.
 */
export async function reorderWorkouts(ids: string[]): Promise<void> {
  const { error } = await supabase.rpc('reorder_workouts', { p_ids: ids });
  if (error) throw error;
}

// ---------------------------------------------------------------------------
// Weekly plans
//
// The schedule is row-level on purpose: every add, remove or move is one `plan_workouts` row, so
// there is no whole-plan payload to lose to a stale tab. The plan name is one `plans` row.
// ---------------------------------------------------------------------------

type WeekPlanRow = {
  id: string;
  name: string;
  updated_at: string;
  plan_workouts: PlanSlot[] | null;
};

function toWeekPlan(row: WeekPlanRow): WeekPlan {
  return {
    id: row.id,
    name: row.name,
    updated_at: row.updated_at,
    slots: [...(row.plan_workouts ?? [])].sort((a, b) => a.weekday - b.weekday),
  };
}

export async function listPlans(): Promise<WeekPlan[]> {
  const { data, error } = await supabase
    .from('plans')
    .select(WEEK_PLAN_SELECT)
    // `created_at` is ordered but not selected, exactly as `position` is for workouts.
    .order('created_at', { ascending: true })
    .order('name', { ascending: true });
  if (error) throw error;
  return (data as unknown as WeekPlanRow[]).map(toWeekPlan);
}

export async function getPlan(id: string): Promise<WeekPlan | null> {
  const { data, error } = await supabase
    .from('plans')
    .select(WEEK_PLAN_SELECT)
    .eq('id', id)
    .maybeSingle();
  if (error) throw error;
  return data ? toWeekPlan(data as unknown as WeekPlanRow) : null;
}

export async function createPlan(name: string): Promise<WeekPlan> {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;

  const { data, error } = await supabase
    .from('plans')
    .insert({ user_id: userData.user.id, name })
    .select(WEEK_PLAN_SELECT)
    .single();
  if (error) throw error;
  return toWeekPlan(data as unknown as WeekPlanRow);
}

export async function renamePlan(id: string, name: string): Promise<void> {
  // `.single()` rather than a bare update: a zero-row result is an error rather than a silent
  // success over a plan that was deleted or is not the caller's.
  const { error } = await supabase.from('plans').update({ name }).eq('id', id).select('id').single();
  if (error) throw error;
}

export async function deletePlan(id: string): Promise<void> {
  const { error } = await supabase.from('plans').delete().eq('id', id);
  if (error) throw error;
}

/** Adds one occurrence. The composite primary key makes "already on that day" a `23505`, which
 * is a no-op rather than an error. */
export async function addPlanWorkout(
  planId: string,
  workoutId: string,
  weekday: Weekday,
): Promise<void> {
  const { error } = await supabase
    .from('plan_workouts')
    .insert({ plan_id: planId, workout_id: workoutId, weekday });
  if (error && !isUniqueViolation(error)) throw error;
}

export async function removePlanWorkout(
  planId: string,
  workoutId: string,
  weekday: Weekday,
): Promise<void> {
  const { error } = await supabase
    .from('plan_workouts')
    .delete()
    .eq('plan_id', planId)
    .eq('workout_id', workoutId)
    .eq('weekday', weekday);
  if (error) throw error;
}

/** Insert the target, then delete the source. If the target already has it, the source is
 * removed rather than duplicating; if the delete then fails, both days show it — visible, not
 * corrupt. */
export async function movePlanWorkout(
  planId: string,
  workoutId: string,
  fromWeekday: Weekday,
  toWeekday: Weekday,
): Promise<void> {
  if (fromWeekday === toWeekday) return;
  await addPlanWorkout(planId, workoutId, toWeekday);
  await removePlanWorkout(planId, workoutId, fromWeekday);
}

// ---------------------------------------------------------------------------
// Exercises
// ---------------------------------------------------------------------------

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
 * Takes only what a person chooses. An exercise carries no rep/time mode: `workout_steps.mode`
 * decides that per workout, so neither form that creates an exercise asks for it.
 *
 * The two side flags are sent explicitly rather than left to the columns' defaults: they are what
 * the checkboxes decide, and the database refuses a row claiming both (`exercises_sides_shape`),
 * so it must be told which is meant rather than left to guess. Note this needs `0012` and `0016`
 * applied — an insert naming a column the database does not have is a `400`, unlike the reads,
 * which tolerate new columns.
 */
export async function createExercise(input: {
  name: string;
  muscle_group: string;
  has_two_sides: boolean;
  alternates_sides: boolean;
}): Promise<Exercise> {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;

  const { data, error } = await supabase
    .from('exercises')
    .insert({
      ...input,
      user_id: userData.user.id,
      slug: null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return data as Exercise;
}

/**
 * Changes what the exercise panel owns: its name, its muscle group, and how it is performed.
 *
 * **Only those columns, not the whole row.** They are sent from the panel's own draft, the same
 * way the name is. Same rule as `createExercise` above: take only what a person chose. (A stale
 * copy written over a change made in another tab is the same exposure the name and group already
 * have, and it is why the panel says out loud what changing the sides does.)
 *
 * **They are not cosmetic.** `has_two_sides` doubles every interval of every workout using this
 * exercise — a set becomes left, then right — and taking it away halves them again;
 * `alternates_sides` keeps one interval per set but changes what a step's rep count means: the
 * total for both sides rather than the number for each.
 *
 * **Named by id, like the deletes.** Not `saveExercise`: `save*` in this file means the whole
 * object upserted (`saveWorkout`), and this is neither whole nor an upsert.
 *
 * **`.select('*').single()` rather than a bare update.** The row that comes back is the one the
 * page renders, so a save needs no second fetch to learn what it just wrote. It also makes a row
 * that is gone an error rather than a silent no-op: `single()` asks PostgREST for
 * `application/vnd.pgrst.object+json`, which a zero-row result answers with an error, whereas a
 * `maybeSingle()` returning null would let the caller report success over a write that never
 * happened. Ownership is the RLS policy's job (`exercises_update`), so there is no `user_id` here:
 * an `eq` on a row you cannot see matches nothing and lands in the same place.
 */
export async function updateExercise(
  id: string,
  patch: {
    name: string;
    muscle_group: string;
    has_two_sides: boolean;
    alternates_sides: boolean;
  },
): Promise<Exercise> {
  const { data, error } = await supabase
    .from('exercises')
    .update(patch)
    .eq('id', id)
    .select('*')
    .single();
  if (error) throw error;
  return data as Exercise;
}

export async function deleteExercise(id: string): Promise<void> {
  const { error } = await supabase.from('exercises').delete().eq('id', id);
  if (error) throw error;
}

/**
 * The names of the workouts holding a step that uses this exercise.
 *
 * `workout_steps.exercise_id` is ON DELETE RESTRICT, so this answers the same question as "may
 * this exercise be deleted" — and it is the answer the user needs, because "a workout" is not one
 * they can act on.
 *
 * Reuses `listWorkouts` rather than writing a new embed: `workout_steps` reaches `workouts`
 * through two joins (block -> workout), and a hand-written PostgREST select string is the most
 * fragile code in this repo (`AGENTS.md`). One account's workout list is small, so the extra rows
 * cost nothing.
 *
 * `workout_steps` is visible through its block and workout under RLS, so a row that blocks a
 * delete is always one this returns — a referenced exercise cannot be held by a workout you
 * cannot see.
 */
export type WorkoutUsage = { id: string; name: string };

export async function workoutsUsingExercise(exerciseId: string): Promise<WorkoutUsage[]> {
  const workouts = await listWorkouts();
  return workouts
    .filter((workout) =>
      workout.blocks.some((block) => block.steps.some((step) => step.exercise_id === exerciseId)),
    )
    .map((workout) => ({ id: workout.id, name: workout.name }));
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

export type SessionSummary = {
  id: string;
  /** The database column is historical and holds the workout's name; see `0018`. */
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
