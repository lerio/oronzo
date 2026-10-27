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
 * Three words, and three only: `workout_steps.intensity` carries a check constraint on the same
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
  /** Performed once per side — left, then right. Doubles the intervals a step emits. */
  has_two_sides: boolean;
  /**
   * Performed on both sides *alternately*, inside one interval.
   *
   * **Not a variety of `has_two_sides`, and the two are mutually exclusive** — the database says
   * so with `exercises_sides_shape`. An alternating exercise is deliberately not two-sided, which
   * is why it needs no change to the flattener at all: `sideSuffixes` returns `[null]` for it and
   * the step emits one interval per set. All this flag buys is the word `(alt)` on the name.
   *
   * **It also changes what a step's rep count means.** Two-sided reads "8 reps" as eight *each*;
   * alternating reads "20 reps" as twenty *altogether* — the interval is emitted once, so the
   * estimate counts it once.
   */
  alternates_sides: boolean;
}

/**
 * How an exercise is performed — the three states its two flags can describe.
 *
 * One value rather than a pair of booleans, in every form that sets it: `exercises_sides_shape`
 * refuses a row claiming both, so "two-sided *and* alternating" is a state that cannot be stored
 * and must not be constructible on screen either.
 */
export type Sides = 'none' | 'two' | 'alternate';

/** The state an exercise is stored in — what a form that edits one starts from. */
export function sidesOf(exercise: Exercise): Sides {
  if (exercise.alternates_sides) return 'alternate';
  return exercise.has_two_sides ? 'two' : 'none';
}

/**
 * A step is an **exercise**, always. Rest is not a kind of step: it comes from a step's
 * `rest_after_seconds` or a block's `rest_between_rounds_seconds`. (`StepKind` still exists
 * and is used by `Interval` — the execution stream really does contain rests, emitted
 * between sets. It is the *workout* that no longer pretends they are steps.)
 */
export interface WorkoutStep {
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
  /** Seconds of "Get in position" before each set of a timed step — and before each side of a
   * two-sided one. Null means none, which is every step until somebody ticks the box.
   *
   * A duration rather than a flag so a per-step value would need no second migration; the
   * builder offers five seconds and nothing else. */
  prepare_seconds: number | null;
}

export interface WorkoutBlock {
  id?: string;
  position: number;
  name: string | null;
  rounds: number;
  rest_between_rounds_seconds: number | null;
  steps: WorkoutStep[];
}

export interface Workout {
  id: string;
  name: string;
  updated_at?: string;
  /** Wall-clock `HH:MM`, normalised in `toWorkout`. Null means "Anytime". */
  preferred_time: string | null;
  blocks: WorkoutBlock[];
}

/** ISO weekday: 1 = Monday … 7 = Sunday, the same convention as SQL and Swift. */
export type Weekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export const WEEKDAYS: { value: Weekday; label: string }[] = [
  { value: 1, label: 'Mon' },
  { value: 2, label: 'Tue' },
  { value: 3, label: 'Wed' },
  { value: 4, label: 'Thu' },
  { value: 5, label: 'Fri' },
  { value: 6, label: 'Sat' },
  { value: 7, label: 'Sun' },
];

/** One scheduled occurrence. A workout can be on several days and in several plans. */
export interface PlanSlot {
  workout_id: string;
  weekday: Weekday;
}

/** A weekly template: no dates, no start or end. It repeats until the user changes it. */
export interface WeekPlan {
  id: string;
  name: string;
  updated_at?: string;
  slots: PlanSlot[];
}

/** "07:00", or "Anytime" when the workout has no preference. */
export function preferredTimeLabel(time: string | null): string {
  return time ?? 'Anytime';
}

/** PostgREST serialises `time` as "07:00:00"; `<input type="time">` wants "07:00". */
export function toInputTime(time: string | null): string {
  return time?.slice(0, 5) ?? '';
}

/** Minutes since midnight. Parsing rather than comparing the strings means "7:00" and "07:00"
 * order the same — the same value `PreferredTime` holds on the Swift side. */
function minutesSinceMidnight(time: string): number {
  const [hour, minute] = time.split(':').map(Number);
  return hour * 60 + minute;
}

/**
 * The same rule as `WeekSchedule.precedes` in Swift: preferred time ascending (null last), then
 * name case-insensitively, then id. Two orderings would put different workouts first on the two
 * surfaces for the same plan.
 */
export function compareWorkoutsByTimeThenName(a: Workout, b: Workout): number {
  const leftTime = a.preferred_time == null ? null : minutesSinceMidnight(a.preferred_time);
  const rightTime = b.preferred_time == null ? null : minutesSinceMidnight(b.preferred_time);

  if (leftTime !== rightTime) {
    if (leftTime == null) return 1;
    if (rightTime == null) return -1;
    return leftTime < rightTime ? -1 : 1;
  }

  const left = a.name.toLowerCase();
  const right = b.name.toLowerCase();
  if (left !== right) return left < right ? -1 : 1;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
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
 * The one-line description of an exercise: its muscle group, and which sides it is done on.
 *
 * No rep count or duration. Whether an exercise runs on reps or on the clock is chosen on the
 * *step* now, so an exercise has no such fact to print — and a default would be a number nothing
 * asks for, which made every line identical.
 *
 * Written once because the exercises list and the workout editor's picker show the same line, and
 * two copies of a formatting rule drift.
 */
export function exerciseSummary(exercise: Exercise): string {
  const parts = [exercise.muscle_group.replace('_', ' ')];
  // It belongs on some rows and not others: it changes what the workout does. It also lands in
  // the picker's filter string, which is what makes "sides" find the two-sided ones and "alt"
  // the alternating ones.
  //
  // The two flags are mutually exclusive, so this is a choice rather than a pair of lines: an
  // alternating exercise is not two-sided, and saying "2 sides" about it would be wrong — it is
  // *one* interval, which is the thing that changed.
  if (exercise.alternates_sides) parts.push('alternating');
  else if (exercise.has_two_sides) parts.push('2 sides');
  return parts.join(' · ');
}

/**
 * The vocabulary offered when an exercise is created — the `<select>` on the Exercises page and
 * in the builder's picker. Not a database enum: `exercises.muscle_group` is plain text
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

/** The same for the prep interval a step's `prepare_seconds` asks for. */
const PREPARE_LABEL = 'Get in position';

/**
 * What marks an interval as done alternatingly — the twin of `WorkoutFlattener.alternatingLabel`.
 *
 * Short because it is drawn on the narrowest two lines in the app and lands on the `NEXT ·`
 * caption too, which shrinks to 70% and then truncates rather than wrapping — so every character
 * is paid for on a 41 mm screen. The cost is that VoiceOver reads it as the word "alt"; that was
 * chosen knowingly, and `docs/decisions.md` has it.
 */
const ALT_LABEL = 'alt';

/**
 * Flatten a workout into the ordered interval sequence the session engine executes.
 *
 *   for block in blocks ordered by position:
 *     for blockRound in 1..block.rounds:
 *       for step in steps ordered by position:
 *         for setIndex in 1..step.sets:
 *           for side in sideSuffixes(step):        // [null], or [left, right]
 *             if step.prepare_seconds: emit prepare   // "Get in position"
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
 * **The prepare is the third synthetic interval, and the only opt-in one.** It is emitted inside
 * the *side* loop, so a two-sided exercise gets one before the left and one before the right,
 * while the rest stays outside it and still falls once for the pair. It never applies to a
 * rep-based step — whose interval cannot count down — nor to a rest, which is emitted from
 * outside the step loop entirely.
 *
 * `exercises` carries the name *and* whether the exercise is done per side, which is why it is a
 * map of `Exercise` rather than of strings. No default: a missing map here is not a visible
 * degradation like a missing name — it is a step that quietly runs once instead of twice.
 */
export function flattenWorkout(workout: Workout, exercises: Map<string, Exercise>): Interval[] {
  const intervals: Interval[] = [];
  const blocks = [...workout.blocks].sort((a, b) => a.position - b.position);

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
            // In front of the interval it prepares for, and inside the side loop, so a two-sided
            // exercise gets one before the left and one before the right. Pushed *first* so both
            // take their index from `intervals.length` at the moment they are built: an index is
            // an interval's identity in the engine, and the two must stay contiguous.
            if (step.prepare_seconds && step.prepare_seconds > 0 && isTimed(step)) {
              intervals.push(
                prepareInterval(
                  intervals.length, step.prepare_seconds, setIndex, Math.max(1, step.sets),
                  blockRound, blockRounds,
                ),
              );
            }

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
 * `WorkoutFlattener.sideSuffixes` in `ios/OronzoCore/` — the same rule, and the same two strings.
 * `estimateWorkoutDuration` reads `.length` from it rather than working the rule out again.
 *
 * **An alternating exercise is not a third case here, and must never become one.** It is not
 * two-sided, so it falls through to `[null]` — one interval per set, which is what "alternating"
 * means. It also decides the rep arithmetic: `estimateWorkoutDuration` multiplies by this length, so
 * an alternating step's reps are counted once, as a total.
 *
 * The reason to keep it that way is the *length*, and only the length: a case returning
 * `['left', 'right']` for an alternating exercise would double both the intervals a workout emits
 * and the reps the estimate allows. (A single-entry case would happen to be harmless — which is
 * exactly why the invariant is worth pinning in a test rather than left to a reader's judgement.)
 */
function sideSuffixes(step: WorkoutStep, exercises: Map<string, Exercise>): (string | null)[] {
  const exercise = step.exercise_id ? exercises.get(step.exercise_id) : undefined;
  return exercise?.has_two_sides ? ['left', 'right'] : [null];
}

/**
 * Whether the interval this step will emit runs against a clock — the same question `toInterval`
 * asks when it chooses between a duration and reps. A step saying `mode: 'time'` with no duration
 * in it emits an interval that cannot count down, and a prepare in front of one would be five
 * seconds before nothing.
 */
function isTimed(step: WorkoutStep): boolean {
  return step.mode === 'time' && (step.duration_seconds ?? 0) > 0;
}

function toInterval(
  step: WorkoutStep,
  index: number,
  setIndex: number,
  side: string | null,
  blockRound: number,
  blockRoundCount: number,
  exercises: Map<string, Exercise>,
): Interval {
  // Resolved once, because the name and the alternating marker below both need it.
  const exercise = step.exercise_id ? exercises.get(step.exercise_id) : undefined;
  // The base name resolves exactly as `WorkoutFlattener.name(for:)` does — label, then the exercise,
  // then a placeholder — so the workout detail screen (which lists a workout as authored) and this
  // (which lists what will actually run) differ only by the suffix appended below. An explicit
  // label takes the side too: it names the exercise, and the exercise is what has two sides.
  const base = step.label || exercise?.name || 'Exercise';
  // A step has a side or is alternating, never both — `exercises_sides_shape` refuses such a row,
  // and the create forms carry one three-way state rather than two independent checkboxes — so the
  // two suffixes cannot collide.
  const name = side
    ? `${base} (${side})`
    : exercise?.alternates_sides
      ? `${base} (${ALT_LABEL})`
      : base;

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

/**
 * The synthetic "get in position" interval a step's `prepare_seconds` asks for.
 *
 * `kind` is `'exercise'`, not a kind of its own: the interval crosses to the Watch whole inside a
 * snapshot, and an unknown `StepKind` would fail to decode *every* snapshot written for a build
 * that predates it — a silent "No workout" on the wrist. As a plain timed interval it is a
 * five-second countdown with the right words already on it, and an older build draws it
 * correctly. It carries the context of the interval it precedes, so the preview can say which set
 * it is getting you ready for, and no step behind it.
 */
function prepareInterval(
  index: number,
  duration: number,
  setIndex: number,
  setCount: number,
  blockRound: number,
  blockRoundCount: number,
): Interval {
  return {
    index,
    kind: 'exercise',
    name: PREPARE_LABEL,
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
 * **The same constant, for the same reason, as `WorkoutSummary.secondsPerRep` in `OronzoCore`.** It
 * is calibrated against a real session: the old Monday plan seed — deleted in the workout/plan
 * split — summed to 32.5 minutes of timed work and rest, and its reps took it to about 50 in
 * practice, so this pace lands the estimate on 45 — the low end of the 45–50 the programme itself
 * claimed, which is the right place for a number read before you start.
 */
const SECONDS_PER_REP = 3.7;

/** A duration, and whether any of it had to be estimated. */
export interface DurationEstimate {
  seconds: number;
  /**
   * True when part of the total is not a duration the workout can prove — a rep target, or a timed
   * step whose length is missing. A surface showing the seconds must say `~` when this is set.
   */
  isEstimate: boolean;
}

/**
 * What the workout will actually take: every timed interval, plus an estimate for the reps.
 *
 * **This used to count only the timed half, and the two surfaces disagreed about the same workout.**
 * The iPhone's `WorkoutSummary` has always estimated rep work; this counted timed seconds alone, so
 * Monday's workout read ~45 min on the phone and ~32m here. The phone is the one that is right —
 * counting only what the data can prove gives a floor for a workout that is half reps, which is a
 * confidently wrong answer rather than a cautious one.
 *
 * The two halves are counted differently, and deliberately so — `WorkoutSummary` in `OronzoCore`
 * does exactly the same, which is the property that matters:
 *
 *  * **timed** work comes off the flattened intervals, so it counts every round of a block;
 *  * **rep** work comes off the authored steps, so a step in a three-round circuit is counted
 *    once, and its estimate is short by two rounds' worth.
 *
 * That second one is a known under-count rather than an oversight — it predates this function —
 * and it is left alone because changing it moves the calibrated numbers in `WorkoutSummaryTests`.
 * What is *not* allowed is the two surfaces disagreeing, which is why both read the side count
 * from the same rule above.
 */
export function estimateWorkoutDuration(
  workout: Workout,
  intervals: Interval[],
  exercises: Map<string, Exercise>,
): DurationEstimate {
  const timed = intervals.reduce((total, i) => total + (i.duration_seconds ?? 0), 0);

  let reps = 0;
  let isEstimate = false;
  for (const block of workout.blocks) {
    for (const step of block.steps) {
      if (step.mode === 'reps') {
        // A two-sided exercise is performed twice per set, so its reps count twice. The count
        // comes from the flattener's own rule rather than a second reading of `has_two_sides`:
        // the timed half above already doubles, because it sums the doubled interval stream, and
        // one total with two opinions in it is worse than either. The same split, and the same
        // fix, as `WorkoutSummary` in `OronzoCore`.
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
  if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`;
  if (m > 0) return sec > 0 ? `${m}m ${sec}s` : `${m}m`;
  return `${sec}s`;
}
