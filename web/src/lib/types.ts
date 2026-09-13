/**
 * Oronzo domain model.
 *
 * This mirrors the Postgres schema in `supabase/migrations/0001_init.sql` and the Swift
 * engine in `ios/Shared/`. The flattening rule below is the contract all three share —
 * if you change it here, change it there too.
 */

export type StepKind = 'exercise' | 'rest';
export type StepMode = 'time' | 'reps';
export type SessionStatus = 'in_progress' | 'completed' | 'abandoned';

export interface Exercise {
  id: string;
  user_id: string | null;
  slug: string | null;
  name: string;
  muscle_group: string;
  equipment: string;
  default_mode: StepMode;
  default_duration_seconds: number | null;
  default_reps: number | null;
  notes: string | null;
}

export interface PlanStep {
  /** Absent on a step that has never been saved. */
  id?: string;
  exercise_id: string | null;
  position: number;
  kind: StepKind;
  label: string | null;
  mode: StepMode;
  duration_seconds: number | null;
  reps: number | null;
  target_weight_kg: number | null;
  rest_after_seconds: number | null;
  notes: string | null;
}

export interface PlanBlock {
  id?: string;
  position: number;
  name: string | null;
  rounds: number;
  rest_between_rounds_seconds: number | null;
  steps: PlanStep[];
}

export interface Plan {
  id: string;
  name: string;
  notes: string | null;
  updated_at?: string;
  blocks: PlanBlock[];
}

/** One entry in the flattened execution sequence. */
export interface Interval {
  index: number;
  kind: StepKind;
  /** What to show on the Watch: the exercise name, or "Break". */
  name: string;
  mode: StepMode | null;
  /** Non-null for timed intervals AND for rest intervals. */
  duration_seconds: number | null;
  reps: number | null;
  target_weight_kg: number | null;
  round_index: number;
  block_index: number;
  block_name: string | null;
}

export const MUSCLE_GROUPS = [
  'chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms',
  'quads', 'hamstrings', 'glutes', 'calves', 'core',
  'full_body', 'cardio', 'mobility',
] as const;

export const EQUIPMENT = [
  'barbell', 'dumbbell', 'kettlebell', 'machine', 'cable',
  'bodyweight', 'band', 'other',
] as const;

const REST_LABEL = 'Break';

/**
 * Flatten a plan into the ordered interval sequence the session engine executes.
 *
 *   for block in blocks ordered by position:
 *     for round in 1..block.rounds:
 *       for step in steps ordered by position:
 *         emit step; if step.rest_after_seconds: emit rest
 *       if round < block.rounds and block.rest_between_rounds_seconds: emit rest
 *
 * Note the deliberate asymmetry: `rest_after_seconds` DOES fire after the final step of a
 * round (usually desired — it doubles as the rest before the next round), whereas
 * `rest_between_rounds_seconds` fires only BETWEEN rounds.
 */
export function flattenPlan(plan: Plan, exerciseNames: Map<string, string>): Interval[] {
  const intervals: Interval[] = [];
  const blocks = [...plan.blocks].sort((a, b) => a.position - b.position);

  blocks.forEach((block, blockIndex) => {
    for (let round = 1; round <= Math.max(1, block.rounds); round++) {
      const steps = [...block.steps].sort((a, b) => a.position - b.position);

      for (const step of steps) {
        intervals.push(toInterval(step, intervals.length, round, blockIndex, block, exerciseNames));

        if (step.rest_after_seconds && step.rest_after_seconds > 0) {
          intervals.push(restInterval(intervals.length, step.rest_after_seconds, round, blockIndex, block));
        }
      }

      const isLastRound = round === Math.max(1, block.rounds);
      if (!isLastRound && block.rest_between_rounds_seconds && block.rest_between_rounds_seconds > 0) {
        intervals.push(restInterval(intervals.length, block.rest_between_rounds_seconds, round, blockIndex, block));
      }
    }
  });

  return intervals;
}

function toInterval(
  step: PlanStep,
  index: number,
  roundIndex: number,
  blockIndex: number,
  block: PlanBlock,
  exerciseNames: Map<string, string>,
): Interval {
  const isRest = step.kind === 'rest';
  const name = isRest
    ? (step.label || REST_LABEL)
    : (step.label || (step.exercise_id ? exerciseNames.get(step.exercise_id) : null) || 'Exercise');

  return {
    index,
    kind: step.kind,
    name,
    mode: isRest ? 'time' : step.mode,
    duration_seconds: isRest ? step.duration_seconds : (step.mode === 'time' ? step.duration_seconds : null),
    reps: isRest ? null : (step.mode === 'reps' ? step.reps : null),
    target_weight_kg: isRest ? null : step.target_weight_kg,
    round_index: roundIndex,
    block_index: blockIndex,
    block_name: block.name,
  };
}

function restInterval(
  index: number,
  duration: number,
  roundIndex: number,
  blockIndex: number,
  block: PlanBlock,
): Interval {
  return {
    index,
    kind: 'rest',
    name: REST_LABEL,
    mode: 'time',
    duration_seconds: duration,
    reps: null,
    target_weight_kg: null,
    round_index: roundIndex,
    block_index: blockIndex,
    block_name: block.name,
  };
}

/** Total planned time; rep-based intervals contribute nothing since their length is unknown. */
export function estimateSeconds(intervals: Interval[]): number {
  return intervals.reduce((total, i) => total + (i.duration_seconds ?? 0), 0);
}

export function formatDuration(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return sec > 0 ? `${m}m ${sec}s` : `${m}m`;
  return `${sec}s`;
}
