/**
 * Oronzo domain model.
 *
 * This mirrors the Postgres schema in `supabase/migrations/` and the Swift engine in
 * `ios/OronzoCore/`. The flattening rule below is the contract all three share — if you
 * change it here, change it there too.
 */

export type StepKind = 'exercise' | 'rest';
export type StepMode = 'time' | 'reps';

/**
 * How hard a timed step is meant to be — the effort, where the duration is the extent.
 *
 * Three words, and three only: `plan_steps.intensity` carries a check constraint on the same
 * three, so a fourth cannot exist in the database. Optional everywhere — a strength hold is just
 * a hold — and only offered in the builder for a timed step.
 */
export type Intensity = 'low' | 'medium' | 'hard';

export const INTENSITIES: Intensity[] = ['low', 'medium', 'hard'];

export interface Exercise {
  id: string;
  user_id: string | null;
  slug: string | null;
  name: string;
  muscle_group: string;
  default_mode: StepMode;
  default_duration_seconds: number | null;
  default_reps: number | null;
  /** Performed once per side — left, then right. Doubles the intervals a step emits. */
  has_two_sides: boolean;
}

/**
 * A step is an **exercise**, always. Rest is not a kind of step: it comes from a step's
 * `rest_after_seconds` or a block's `rest_between_rounds_seconds`. (`StepKind` still exists
 * and is used by `Interval` — the execution stream really does contain rests, emitted
 * between sets. It is the *plan* that no longer pretends they are steps.)
 */
export interface PlanStep {
  /** Absent on a step that has never been saved. */
  id?: string;
  exercise_id: string | null;
  position: number;
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
  /** How hard this step is meant to be, for a timed one. Null means nobody said. */
  intensity: Intensity | null;
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
  updated_at?: string;
  blocks: PlanBlock[];
}

/** One entry in the flattened execution sequence. */
export interface Interval {
  index: number;
  kind: StepKind;
  /** What to show on the Watch: the exercise name, or "Break". */
  name: string;
  /** Non-null for timed intervals AND for rest intervals. */
  duration_seconds: number | null;
  reps: number | null;
  target_weight_kg: number | null;
  /** Which set of the exercise this is (1-based). */
  set_index: number;
  /** How many sets that exercise has — so the UI can say "set 2 of 4". */
  set_count: number;
  /** Which round of the enclosing block this is (1-based). */
  block_round: number;
  /** How many rounds that block has. */
  block_round_count: number;
  /** The step's word for the effort, carried through untouched. Null for most intervals. */
  intensity: Intensity | null;
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

/**
 * The one-line description of an exercise: its muscle group, and a duration for a timed one.
 *
 * No rep count. A rep-based exercise's `default_reps` is a constant nothing asks for — 10, set
 * when the row is created and only ever edited per plan step — so printing it made every line
 * identical and none of them informative. A duration is the other way round: a timed exercise
 * cannot exist without one, and it is the number its step will actually run.
 *
 * Written once because the exercises list and the plan editor's picker show the same line, and
 * two copies of a formatting rule drift.
 */
export function exerciseSummary(exercise: Exercise): string {
  const parts = [exercise.muscle_group.replace('_', ' ')];
  if (exercise.default_mode === 'time') {
    parts.push(formatDuration(exercise.default_duration_seconds ?? 0));
  }
  // Unlike the rep count this replaced, it belongs on some rows and not others: it changes what
  // the workout does. It also lands in the picker's filter string, so "sides" finds these.
  if (exercise.has_two_sides) parts.push('2 sides');
  return parts.join(' · ');
}

/**
 * The vocabulary offered when an exercise is created — the two `<select>`s, on the Exercises
 * page and in the builder's picker. Not a database enum: `exercises.muscle_group` is plain text
 * with no check constraint (unlike `intensity`), so this list constrains nothing that is already
 * stored, and a row carrying a group since removed from here still reads and filters fine.
 *
 * The first eleven are muscle groups, roughly top to bottom. The last four are not muscles at
 * all — they answer "what kind of session is this" — so they sit together at the end.
 */
export const MUSCLE_GROUPS = [
  'chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms',
  'quads', 'hamstrings', 'glutes', 'calves', 'core',
  'full_body', 'cardio', 'mobility', 'mindfulness',
] as const;

const REST_LABEL = 'Break';

/**
 * Flatten a plan into the ordered interval sequence the session engine executes.
 *
 *   for block in blocks ordered by position:
 *     for blockRound in 1..block.rounds:
 *       for step in steps ordered by position:
 *         for setIndex in 1..step.sets:
 *           for side in sideSuffixes(step):        // [null], or [left, right]
 *             emit step, named "… (left)" / "… (right)" when there is a side
 *           if step.rest_after_seconds: emit rest  // once per set, after the pair
 *       if blockRound < block.rounds and block.rest_between_rounds_seconds: emit rest
 *
 * Both an exercise and a block can repeat, and the two words mean different things: a step's
 * `sets` is its set count ("4 x 8 bench press"), while a block's `rounds` repeats a whole
 * group ("6 x (20s hard, 40s easy)"). A two-sided exercise is neither — it doubles *within* a
 * set, and both halves carry the same set number.
 *
 * The two rest mechanisms differ deliberately: `rest_after_seconds` fires after EVERY set
 * including the last, so an exercise's rest carries you into the next exercise, whereas
 * `rest_between_rounds_seconds` fires only BETWEEN a block's rounds.
 *
 * `exercises` carries the name *and* whether the exercise is done per side, which is why it is a
 * map of `Exercise` rather than of strings. No default: a missing map here is not a visible
 * degradation like a missing name — it is a step that quietly runs once instead of twice.
 */
export function flattenPlan(plan: Plan, exercises: Map<string, Exercise>): Interval[] {
  const intervals: Interval[] = [];
  const blocks = [...plan.blocks].sort((a, b) => a.position - b.position);

  blocks.forEach((block) => {
    const blockRounds = Math.max(1, block.rounds);
    // Sorted once, outside the loop: this used to re-sort the same steps on every round, so a
    // five-round circuit allocated and sorted five identical arrays.
    const steps = [...block.steps].sort((a, b) => a.position - b.position);

    for (let blockRound = 1; blockRound <= blockRounds; blockRound++) {

      for (const step of steps) {
        for (let setIndex = 1; setIndex <= Math.max(1, step.sets); setIndex++) {
          // A two-sided exercise emits both sides here, so the rest below still falls once per
          // set — after the pair, which is what "a set of lunges" means when you are doing them.
          for (const side of sideSuffixes(step, exercises)) {
            intervals.push(
              toInterval(step, intervals.length, setIndex, side, blockRound, blockRounds, exercises),
            );
          }

          if (step.rest_after_seconds && step.rest_after_seconds > 0) {
            intervals.push(
              restInterval(
                intervals.length, step.rest_after_seconds, setIndex, Math.max(1, step.sets),
                blockRound, blockRounds,
              ),
            );
          }
        }
      }

      if (blockRound < blockRounds && block.rest_between_rounds_seconds && block.rest_between_rounds_seconds > 0) {
        intervals.push(
          restInterval(
            intervals.length, block.rest_between_rounds_seconds, blockRound, 1,
            blockRound, blockRounds,
          ),
        );
      }
    }
  });

  return intervals;
}

/**
 * The name suffixes a step is performed with, in order: one entry — `null`, meaning no suffix —
 * when the exercise is done once, two when it is done per side.
 *
 * This is the whole of "has two sides" as the preview sees it, and the twin of
 * `PlanFlattener.sideSuffixes` in `ios/OronzoCore/` — the same rule, and the same two strings.
 * `estimatePlanDuration` reads `.length` from it rather than working the rule out again.
 */
function sideSuffixes(step: PlanStep, exercises: Map<string, Exercise>): (string | null)[] {
  const exercise = step.exercise_id ? exercises.get(step.exercise_id) : undefined;
  return exercise?.has_two_sides ? ['left', 'right'] : [null];
}

function toInterval(
  step: PlanStep,
  index: number,
  setIndex: number,
  side: string | null,
  blockRound: number,
  blockRoundCount: number,
  exercises: Map<string, Exercise>,
): Interval {
  // The base name resolves exactly as `PlanFlattener.name(for:)` does — label, then the exercise,
  // then a placeholder — so the plan detail screen (which lists a plan as authored) and this
  // (which lists what will actually run) differ only by the suffix appended below. An explicit
  // label takes the side too: it names the exercise, and the exercise is what has two sides.
  const base =
    step.label || (step.exercise_id ? exercises.get(step.exercise_id)?.name : null) || 'Exercise';
  const name = side ? `${base} (${side})` : base;

  return {
    index,
    kind: 'exercise',
    name,
    duration_seconds: step.mode === 'time' ? step.duration_seconds : null,
    reps: step.mode === 'reps' ? step.reps : null,
    target_weight_kg: step.target_weight_kg,
    set_index: setIndex,
    set_count: Math.max(1, step.sets),
    block_round: blockRound,
    block_round_count: blockRoundCount,
    // Carried straight through: it is the step's own word, and the side above is the only thing
    // this function decides.
    intensity: step.intensity,
  };
}

function restInterval(
  index: number,
  duration: number,
  setIndex: number,
  setCount: number,
  blockRound: number,
  blockRoundCount: number,
): Interval {
  return {
    index,
    kind: 'rest',
    name: REST_LABEL,
    duration_seconds: duration,
    reps: null,
    target_weight_kg: null,
    set_index: setIndex,
    set_count: setCount,
    block_round: blockRound,
    block_round_count: blockRoundCount,
    intensity: null,
  };
}

/**
 * How long a rep-based set takes, per rep.
 *
 * **The same constant, for the same reason, as `PlanSummary.secondsPerRep` in `OronzoCore`.** It
 * is calibrated against a real session: `supabase/plans/monday-upper-body-a.sql` sums to 32.5
 * minutes of timed work and rest, and its reps take it to about 50 in practice, so this pace lands
 * the estimate on 45 — the low end of the 45–50 the programme itself claims, which is the right
 * place for a number read before you start.
 */
const SECONDS_PER_REP = 3.7;

/** A duration, and whether any of it had to be estimated. */
export interface DurationEstimate {
  seconds: number;
  /**
   * True when part of the total is not a duration the plan can prove — a rep target, or a timed
   * step whose length is missing. A surface showing the seconds must say `~` when this is set.
   */
  isEstimate: boolean;
}

/**
 * What the workout will actually take: every timed interval, plus an estimate for the reps.
 *
 * **This used to count only the timed half, and the two surfaces disagreed about the same plan.**
 * The iPhone's `PlanSummary` has always estimated rep work; this counted timed seconds alone, so
 * Monday's plan read ~45 min on the phone and ~32m here. The phone is the one that is right —
 * counting only what the data can prove gives a floor for a workout that is half reps, which is a
 * confidently wrong answer rather than a cautious one.
 *
 * The two halves are counted differently, and deliberately so — `PlanSummary` in `OronzoCore`
 * does exactly the same, which is the property that matters:
 *
 *  * **timed** work comes off the flattened intervals, so it counts every round of a block;
 *  * **rep** work comes off the authored steps, so a step in a three-round circuit is counted
 *    once, and its estimate is short by two rounds' worth.
 *
 * That second one is a known under-count rather than an oversight — it predates this function —
 * and it is left alone because changing it moves the calibrated numbers in `PlanSummaryTests`.
 * What is *not* allowed is the two surfaces disagreeing, which is why both read the side count
 * from the same rule above.
 */
export function estimatePlanDuration(
  plan: Plan,
  intervals: Interval[],
  exercises: Map<string, Exercise>,
): DurationEstimate {
  const timed = intervals.reduce((total, i) => total + (i.duration_seconds ?? 0), 0);

  let reps = 0;
  let isEstimate = false;
  for (const block of plan.blocks) {
    for (const step of block.steps) {
      if (step.mode === 'reps') {
        // A two-sided exercise is performed twice per set, so its reps count twice. The count
        // comes from the flattener's own rule rather than a second reading of `has_two_sides`:
        // the timed half above already doubles, because it sums the doubled interval stream, and
        // one total with two opinions in it is worse than either. The same split, and the same
        // fix, as `PlanSummary` in `OronzoCore`.
        const sides = sideSuffixes(step, exercises).length;
        reps += sides * step.sets * (step.reps ?? 0) * SECONDS_PER_REP;
        isEstimate = true;
      } else if (step.duration_seconds == null) {
        isEstimate = true;
      }
    }
  }

  return { seconds: timed + reps, isEstimate };
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
