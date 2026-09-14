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
  /** How many times this exercise repeats — its set count. (A block's `rounds`
   * repeats a whole group; the two are deliberately different words.) */
  sets: number;
  mode: StepMode;
  duration_seconds: number | null;
  /** The rep target. */
  reps: number | null;
  target_weight_kg: number | null;
  rest_after_seconds: number | null;
  /** Free-form guidance: "per side", "1–2 reps in reserve". */
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
  /** Which set of the exercise this is (1-based). */
  set_index: number;
  /** Which round of the enclosing block this is. */
  block_round: number;
  block_index: number;
  block_name: string | null;
}

/** "10 reps", or null for a timed interval. */
export function repsDisplay(interval: Interval): string | null {
  if (interval.reps == null) return null;
  return `${interval.reps} reps`;
}

/** Whole numbers lose their trailing ".0"; halves keep theirs. */
function formatNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

/** "20 kg", or null when nothing is prescribed. */
export function weightDisplay(interval: Interval): string | null {
  if (interval.target_weight_kg == null) return null;
  return `${formatNumber(interval.target_weight_kg)} kg`;
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
 *     for blockRound in 1..block.rounds:
 *       for step in steps ordered by position:
 *         for setIndex in 1..step.sets:
 *           emit step; if step.rest_after_seconds: emit rest
 *       if blockRound < block.rounds and block.rest_between_rounds_seconds: emit rest
 *
 * Both an exercise and a block can repeat, and the two words mean different things: a step's
 * `sets` is its set count ("4 x 6-8 bench press"), while a block's `rounds` repeats a whole
 * group ("6 x (20s hard, 40s easy)").
 *
 * The two rest mechanisms differ deliberately: `rest_after_seconds` fires after EVERY set
 * including the last, so an exercise's rest carries you into the next exercise, whereas
 * `rest_between_rounds_seconds` fires only BETWEEN a block's rounds.
 */
export function flattenPlan(plan: Plan, exerciseNames: Map<string, string>): Interval[] {
  const intervals: Interval[] = [];
  const blocks = [...plan.blocks].sort((a, b) => a.position - b.position);

  blocks.forEach((block, blockIndex) => {
    const blockRounds = Math.max(1, block.rounds);

    for (let blockRound = 1; blockRound <= blockRounds; blockRound++) {
      const steps = [...block.steps].sort((a, b) => a.position - b.position);

      for (const step of steps) {
        for (let setIndex = 1; setIndex <= Math.max(1, step.sets); setIndex++) {
          intervals.push(
            toInterval(step, intervals.length, setIndex, blockRound, blockIndex, block, exerciseNames),
          );

          if (step.rest_after_seconds && step.rest_after_seconds > 0) {
            intervals.push(
              restInterval(intervals.length, step.rest_after_seconds, setIndex, blockRound, blockIndex, block),
            );
          }
        }
      }

      if (blockRound < blockRounds && block.rest_between_rounds_seconds && block.rest_between_rounds_seconds > 0) {
        intervals.push(
          restInterval(intervals.length, block.rest_between_rounds_seconds, blockRound, blockRound, blockIndex, block),
        );
      }
    }
  });

  return intervals;
}

function toInterval(
  step: PlanStep,
  index: number,
  setIndex: number,
  blockRound: number,
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
    set_index: setIndex,
    block_round: blockRound,
    block_index: blockIndex,
    block_name: block.name,
  };
}

function restInterval(
  index: number,
  duration: number,
  setIndex: number,
  blockRound: number,
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
    set_index: setIndex,
    block_round: blockRound,
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
