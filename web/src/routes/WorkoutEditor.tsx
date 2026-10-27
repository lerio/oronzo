import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import ExercisePicker from '../components/ExercisePicker';
import { addPlanWorkout, getWorkout, listExercises, listPlans, saveWorkout } from '../lib/api';
import { errorMessage } from '../lib/errors';
import {
  INTENSITIES,
  WEEKDAYS,
  estimateWorkoutDuration,
  flattenWorkout,
  formatDuration,
  repsDisplay,
  toInputTime,
  weightDisplay,
  type Exercise,
  type Intensity,
  type StepMode,
  type WeekPlan,
  type Weekday,
  type Workout,
  type WorkoutBlock,
  type WorkoutStep,
} from '../lib/types';

const blankWorkout = (): Workout => ({ id: '', name: '', preferred_time: null, blocks: [] });

/** What the "get in position" checkbox writes. The column is a duration so that a per-step value
 * would need no second migration; five seconds is the only value there is for now. */
const PREPARE_SECONDS = 5;

/** What switching a step to a mode fills in when that mode has no value yet. */
const DEFAULT_REPS = 10;
const DEFAULT_DURATION_SECONDS = 45;

/** Offered as chips next to the time input. Any other time can be picked with the input. */
const TIME_PRESETS = [
  { label: 'Morning', time: '07:00' },
  { label: 'Midday', time: '12:00' },
  { label: 'Evening', time: '18:00' },
];

function stepFromExercise(exercise?: Exercise): WorkoutStep {
  return {
    exercise_id: exercise?.id ?? null,
    position: 0,
    label: null,
    sets: 1,
    // Reps until the author says otherwise: the mode belongs to the step now, so the same
    // exercise can run on reps in one workout and on the clock in another.
    mode: 'reps',
    duration_seconds: null,
    reps: DEFAULT_REPS,
    target_weight_kg: null,
    rest_after_seconds: null,
    // Optional, so a freshly-picked timed step starts with none and the row offers "—". The
    // builder is where the effort is chosen; nothing else can dictate it, because a HIIT block
    // runs the same movement hard and easy.
    intensity: null,
    // Opt-in, and off until somebody ticks it: a timed step is not always work — the seeded HIIT
    // blocks prescribe their recoveries as timed steps too, and nothing tells those apart from a
    // hold. See `flattenWorkout`.
    prepare_seconds: null,
  };
}

/**
 * Switching a step between reps and time.
 *
 * The field the new mode needs is filled in when it is missing — `workout_steps_mode_shape`
 * refuses a timed step with no duration and a rep step with no rep target. The other mode's
 * fields are cleared rather than left set-but-hidden: the flattener carries `intensity` and
 * `target_weight_kg` into the interval whatever the mode, so a stale one would show up in the
 * preview on an interval it does not describe.
 */
function modePatch(step: WorkoutStep, mode: StepMode): Partial<WorkoutStep> {
  return mode === 'time'
    ? {
        mode,
        duration_seconds: step.duration_seconds ?? DEFAULT_DURATION_SECONDS,
        reps: null,
        target_weight_kg: null,
      }
    : {
        mode,
        reps: step.reps ?? DEFAULT_REPS,
        duration_seconds: null,
        intensity: null,
        prepare_seconds: null,
      };
}

/** Re-index positions from array order — positions must always be contiguous per parent. */
function normalize(workout: Workout): Workout {
  return {
    ...workout,
    blocks: workout.blocks.map((block, blockIndex) => ({
      ...block,
      position: blockIndex,
      steps: block.steps.map((step, stepIndex) => ({ ...step, position: stepIndex })),
    })),
  };
}

/**
 * Mirrors the DB's workout_steps_mode_shape constraint, so problems surface before a failed save
 * rather than as a raw Postgres error.
 */
function stepProblem(step: WorkoutStep): string | null {
  if (!step.exercise_id) return 'Pick an exercise';
  if (step.mode === 'time' && !step.duration_seconds) return 'Needs a duration';
  if (step.mode === 'reps' && !step.reps) return 'Needs a rep target';
  return null;
}

export default function WorkoutEditor() {
  const { id } = useParams();
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const isNew = !id;

  /** Set by the week board: after a save, schedule the new workout and return to that plan. */
  const planId = params.get('plan');
  const weekdayParam = params.get('weekday');
  const returnWeekday = weekdayParam != null && /^[1-7]$/.test(weekdayParam)
    ? (Number(weekdayParam) as Weekday)
    : null;

  const [workout, setWorkout] = useState<Workout | null>(null);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [plans, setPlans] = useState<WeekPlan[]>([]);
  const [plansUnavailable, setPlansUnavailable] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedAt, setSavedAt] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        // In parallel: the requests do not depend on each other, and awaiting them in turn made
        // opening an existing workout two round trips deep instead of one.
        const [loadedExercises, found, loadedPlans] = await Promise.all([
          listExercises(),
          isNew ? Promise.resolve(null) : getWorkout(id!),
          // The "Scheduled in" line is secondary: a plan fetch failure must not block editing.
          listPlans().catch(() => {
            setPlansUnavailable(true);
            setError('Could not load plan memberships.');
            return [] as WeekPlan[];
          }),
        ]);
        if (cancelled) return;
        setExercises(loadedExercises);
        setPlans(loadedPlans);
        setWorkout(isNew ? blankWorkout() : (found ?? blankWorkout()));
      } catch (err) {
        if (!cancelled) setError(errorMessage(err, 'Could not load workout'));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id, isNew]);

  // The exercises themselves, not just their names: flattening reads whether each one is done
  // per side as well, which is what decides how many intervals a step becomes.
  const exercisesById = useMemo(
    () => new Map(exercises.map((exercise) => [exercise.id, exercise])),
    [exercises],
  );

  const preview = useMemo(
    () => (workout ? flattenWorkout(workout, exercisesById) : []),
    [workout, exercisesById],
  );

  // `exercisesById` is listed as well as `preview`, rather than relied on through it: the rep
  // half of the estimate reads the map directly, so a changed map with an unchanged preview
  // would otherwise leave the total stale.
  const duration = useMemo(
    () => (workout
      ? estimateWorkoutDuration(workout, preview, exercisesById)
      : { seconds: 0, isEstimate: false }),
    [workout, preview, exercisesById],
  );

  // Per step, in the workout's own shape, so each row below can index straight into it. Flattened
  // it would lose which step each problem belongs to, and the row would have to work it out again.
  const stepProblems = useMemo(
    () => workout?.blocks.map((block) => block.steps.map(stepProblem)) ?? [],
    [workout],
  );
  const problemCount = stepProblems.reduce(
    (total, block) => total + block.filter((problem) => problem !== null).length,
    0,
  );

  const memberships = useMemo(() => {
    if (!workout || isNew) return [];
    return plans.flatMap((plan) => {
      const days = plan.slots
        .filter((slot) => slot.workout_id === workout.id)
        .map((slot) => WEEKDAYS.find((day) => day.value === slot.weekday)?.label ?? '');
      return days.length > 0 ? [`${plan.name} · ${days.join(', ')}`] : [];
    });
  }, [plans, workout, isNew]);

  if (!workout) return <p className="muted">{error ?? 'Loading…'}</p>;

  const mutate = (fn: (draft: Workout) => Workout) =>
    setWorkout((current) => (current ? normalize(fn(current)) : current));

  const setPreferredTime = (time: string | null) =>
    mutate((draft) => ({ ...draft, preferred_time: time }));

  const updateBlock = (blockIndex: number, patch: Partial<WorkoutBlock>) =>
    mutate((draft) => ({
      ...draft,
      blocks: draft.blocks.map((block, i) => (i === blockIndex ? { ...block, ...patch } : block)),
    }));

  const updateStep = (blockIndex: number, stepIndex: number, patch: Partial<WorkoutStep>) =>
    mutate((draft) => ({
      ...draft,
      blocks: draft.blocks.map((block, i) =>
        i === blockIndex
          ? { ...block, steps: block.steps.map((step, j) => (j === stepIndex ? { ...step, ...patch } : step)) }
          : block,
      ),
    }));

  const addBlock = () =>
    mutate((draft) => ({
      ...draft,
      blocks: [
        ...draft.blocks,
        {
          position: draft.blocks.length,
          name: draft.blocks.length === 0 ? 'Main' : null,
          rounds: 1,
          rest_between_rounds_seconds: null,
          steps: [],
        },
      ],
    }));

  const removeBlock = (blockIndex: number) =>
    mutate((draft) => ({ ...draft, blocks: draft.blocks.filter((_, i) => i !== blockIndex) }));

  const moveBlock = (blockIndex: number, delta: number) =>
    mutate((draft) => {
      const blocks = [...draft.blocks];
      const target = blockIndex + delta;
      if (target < 0 || target >= blocks.length) return draft;
      [blocks[blockIndex], blocks[target]] = [blocks[target], blocks[blockIndex]];
      return { ...draft, blocks };
    });

  const addStep = (blockIndex: number, step: WorkoutStep) =>
    mutate((draft) => ({
      ...draft,
      blocks: draft.blocks.map((block, i) => (i === blockIndex ? { ...block, steps: [...block.steps, step] } : block)),
    }));

  /**
   * An exercise created from inside the picker. It has to land in `exercises`, because that is
   * what the flatten preview resolves names against and what the picker looks its selection up
   * in — without it a step would point at an exercise nothing could name.
   */
  const addExercise = (exercise: Exercise) =>
    setExercises((current) => [...current, exercise]);

  const removeStep = (blockIndex: number, stepIndex: number) =>
    mutate((draft) => ({
      ...draft,
      blocks: draft.blocks.map((block, i) =>
        i === blockIndex ? { ...block, steps: block.steps.filter((_, j) => j !== stepIndex) } : block,
      ),
    }));

  const moveStep = (blockIndex: number, stepIndex: number, delta: number) =>
    mutate((draft) => ({
      ...draft,
      blocks: draft.blocks.map((block, i) => {
        if (i !== blockIndex) return block;
        const steps = [...block.steps];
        const target = stepIndex + delta;
        if (target < 0 || target >= steps.length) return block;
        [steps[stepIndex], steps[target]] = [steps[target], steps[stepIndex]];
        return { ...block, steps };
      }),
    }));

  /**
   * The picker hands back the exercise itself, not an id to look up. That matters for one it
   * just created: `exercises` is state, so in this same handler the new row is not in it yet —
   * looking it up by id would find nothing and quietly leave the step unpicked.
   */
  function changeExercise(blockIndex: number, stepIndex: number, exercise: Exercise) {
    updateStep(blockIndex, stepIndex, stepFromExercise(exercise));
  }

  async function onSave() {
    if (!workout) return;
    if (!workout.name.trim()) {
      setError('Give the workout a name first.');
      return;
    }
    if (problemCount > 0) {
      setError(`Fix ${problemCount} step${problemCount === 1 ? '' : 's'} before saving.`);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const savedId = await saveWorkout(workout);
      setSavedAt(new Date().toLocaleTimeString());

      // The week board's "New workout for <day>" / "New workout" paths come back here. The
      // membership is a separate row by design; a 23505 (already on that day) is a no-op.
      if (planId) {
        if (returnWeekday != null) {
          await addPlanWorkout(planId, savedId, returnWeekday);
        }
        navigate(`/plans/${planId}`);
        return;
      }

      if (isNew) navigate(`/workouts/${savedId}`, { replace: true });
    } catch (err) {
      setError(errorMessage(err, 'Save failed'));
    } finally {
      setSaving(false);
    }
  }

  return (
    <section>
      <div className="page-head">
        <h1>{isNew ? 'New workout' : 'Edit workout'}</h1>
        <div className="head-actions">
          {savedAt && <span className="muted small">Saved {savedAt}</span>}
          <button className="primary" onClick={() => void onSave()} disabled={saving}>
            {saving ? 'Saving…' : 'Save workout'}
          </button>
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      <div className="card">
        <label className="field">
          <span>Name</span>
          <input
            value={workout.name}
            placeholder="e.g. Push A"
            onChange={(e) => mutate((draft) => ({ ...draft, name: e.target.value }))}
          />
        </label>

        <div className="field">
          <span>Preferred time</span>
          <div className="time-choices">
            <button
              type="button"
              className={workout.preferred_time === null ? 'time-choice active' : 'time-choice'}
              onClick={() => setPreferredTime(null)}
            >
              Anytime
            </button>
            {TIME_PRESETS.map((preset) => (
              <button
                key={preset.time}
                type="button"
                className={workout.preferred_time === preset.time ? 'time-choice active' : 'time-choice'}
                onClick={() => setPreferredTime(preset.time)}
              >
                {preset.label} <span className="muted small">{preset.time}</span>
              </button>
            ))}
            <input
              type="time"
              value={toInputTime(workout.preferred_time)}
              onChange={(e) => setPreferredTime(e.target.value || null)}
              aria-label="Custom preferred time"
            />
          </div>
          <p className="muted small">
            Used to order the day on the phone and in the week board.
          </p>
        </div>

        <p className="muted small">
          {isNew
            ? 'Save it, then schedule it into a weekly plan.'
            : plansUnavailable
              ? 'Plan memberships unavailable.'
              : memberships.length > 0
                ? `Scheduled in ${memberships.join('; ')}.`
                : 'Not in a plan yet.'}
        </p>
      </div>

      <div className="summary-bar">
        <span>
          {workout.blocks.length} block{workout.blocks.length === 1 ? '' : 's'} · {preview.length} interval
          {preview.length === 1 ? '' : 's'}
          {duration.seconds > 0 &&
            ` · ${duration.isEstimate ? '~' : ''}${formatDuration(duration.seconds)}`}
        </span>
        <span className="muted small">
          An exercise's <em>sets</em> is its set count; a block's <em>rounds</em> repeats the whole
          group — that is how circuits are expressed.
        </span>
      </div>

      {workout.blocks.map((block, blockIndex) => (
        <div key={blockIndex} className="card block-card">
          <div className="block-head">
            <input
              className="block-name"
              placeholder={`Block ${blockIndex + 1}`}
              value={block.name ?? ''}
              onChange={(e) => updateBlock(blockIndex, { name: e.target.value || null })}
            />
            <label className="inline-field">
              <span>rounds</span>
              <input
                className="w-digits-2"
                type="number"
                min={1}
                value={block.rounds}
                onChange={(e) => updateBlock(blockIndex, { rounds: Math.max(1, Number(e.target.value) || 1) })}
              />
            </label>
            <label className="inline-field">
              <span>rest between rounds (s)</span>
              <input
                className="w-digits-3"
                type="number"
                min={0}
                placeholder="—"
                value={block.rest_between_rounds_seconds ?? ''}
                onChange={(e) =>
                  updateBlock(blockIndex, {
                    rest_between_rounds_seconds: e.target.value === '' ? null : Number(e.target.value),
                  })
                }
              />
            </label>
            <div className="row-actions">
              <button className="icon-btn" onClick={() => moveBlock(blockIndex, -1)} title="Move up">
                ↑
              </button>
              <button className="icon-btn" onClick={() => moveBlock(blockIndex, 1)} title="Move down">
                ↓
              </button>
              <button
                className="icon-btn danger"
                onClick={() => removeBlock(blockIndex)}
                title="Remove block"
              >
                ×
              </button>
            </div>
          </div>

          {block.steps.length === 0 && (
            <p className="muted small">No steps yet — add one below.</p>
          )}

          {block.steps.map((step, stepIndex) => {
            const problem = stepProblems[blockIndex]?.[stepIndex] ?? null;
            return (
              <div key={stepIndex} className={problem ? 'step-row invalid' : 'step-row'}>
                <span className="step-index">{stepIndex + 1}</span>

                <ExercisePicker
                  exercises={exercises}
                  value={step.exercise_id}
                  onChange={(exercise) => changeExercise(blockIndex, stepIndex, exercise)}
                  onCreated={addExercise}
                />

                {/* Nothing belongs to a step until it has an exercise. Which fields apply — a
                    rep target and a load, or a duration — is the step's own mode, chosen below;
                    before an exercise is picked there is nothing here that would not be a guess. */}
                {step.exercise_id && (
                  <>
                    <label className="inline-field" title="How many times this exercise repeats — its set count">
                      <span>sets</span>
                      <input
                        className="w-digits-2"
                        type="number"
                        min={1}
                        value={step.sets}
                        onChange={(e) =>
                          updateStep(blockIndex, stepIndex, { sets: Math.max(1, Number(e.target.value) || 1) })
                        }
                      />
                    </label>

                    {/* Both modes are always offered: an exercise can be a rep target in one
                        workout and a hold in another. */}
                    <label
                      className="inline-field"
                      title="Whether this step runs on a rep target or on the clock"
                    >
                      <span>mode</span>
                      <select
                        value={step.mode}
                        onChange={(e) =>
                          updateStep(
                            blockIndex,
                            stepIndex,
                            modePatch(step, e.target.value as StepMode),
                          )
                        }
                      >
                        <option value="reps">reps</option>
                        <option value="time">time</option>
                      </select>
                    </label>

                    {step.mode === 'time' ? (
                      <>
                        <label className="inline-field">
                          <span>sec</span>
                          <input
                            className="w-digits-3"
                            type="number"
                            min={1}
                            value={step.duration_seconds ?? ''}
                            onChange={(e) =>
                              updateStep(blockIndex, stepIndex, { duration_seconds: Number(e.target.value) || null })
                            }
                          />
                        </label>

                        <label
                          className="inline-field"
                          title="How hard this interval is meant to be — shown while it runs"
                        >
                          <span>intensity</span>
                          <select
                            value={step.intensity ?? ''}
                            onChange={(e) =>
                              updateStep(blockIndex, stepIndex, {
                                intensity: e.target.value === '' ? null : (e.target.value as Intensity),
                              })
                            }
                          >
                            <option value="">—</option>
                            {INTENSITIES.map((level) => (
                              <option key={level} value={level}>
                                {level}
                              </option>
                            ))}
                          </select>
                        </label>

                        <label
                          className="inline-field"
                          title="A five-second 'Get in position' before each set of this exercise"
                        >
                          <input
                            type="checkbox"
                            checked={step.prepare_seconds != null}
                            onChange={(e) =>
                              updateStep(blockIndex, stepIndex, {
                                prepare_seconds: e.target.checked ? PREPARE_SECONDS : null,
                              })
                            }
                          />
                          <span>Get in position</span>
                        </label>
                      </>
                    ) : (
                      <>
                        <label className="inline-field">
                          <span>reps</span>
                          <input
                            className="w-digits-2"
                            type="number"
                            min={1}
                            value={step.reps ?? ''}
                            onChange={(e) =>
                              updateStep(blockIndex, stepIndex, { reps: Number(e.target.value) || null })
                            }
                          />
                        </label>

                        <label className="inline-field">
                          <span>kg</span>
                          <input
                            className="w-weight"
                            type="number"
                            min={0}
                            step="0.5"
                            placeholder="—"
                            value={step.target_weight_kg ?? ''}
                            onChange={(e) =>
                              updateStep(blockIndex, stepIndex, {
                                target_weight_kg: e.target.value === '' ? null : Number(e.target.value),
                              })
                            }
                          />
                        </label>
                      </>
                    )}

                    <label
                      className="inline-field"
                      title="Rest after each set of this exercise, including the last — so it carries you into the next exercise"
                    >
                      <span>rest between sets (s)</span>
                      <input
                        className="w-digits-3"
                        type="number"
                        min={0}
                        placeholder="—"
                        value={step.rest_after_seconds ?? ''}
                        onChange={(e) =>
                          updateStep(blockIndex, stepIndex, {
                            rest_after_seconds: e.target.value === '' ? null : Number(e.target.value),
                          })
                        }
                      />
                    </label>
                  </>
                )}

                <div className="row-actions">
                  <button className="icon-btn" onClick={() => moveStep(blockIndex, stepIndex, -1)}>
                    ↑
                  </button>
                  <button className="icon-btn" onClick={() => moveStep(blockIndex, stepIndex, 1)}>
                    ↓
                  </button>
                  <button
                    className="icon-btn danger"
                    onClick={() => removeStep(blockIndex, stepIndex)}
                  >
                    ×
                  </button>
                </div>

                {problem && <span className="step-problem">{problem}</span>}
              </div>
            );
          })}

          <div className="step-add">
            {/* Deliberately no exercise: the row opens as just a picker and grows its fields
                once an exercise is chosen, with the mode defaulted to reps. */}
            <button className="link-btn" onClick={() => addStep(blockIndex, stepFromExercise())}>
              + exercise
            </button>
          </div>
        </div>
      ))}

      <button className="secondary" onClick={addBlock}>
        + Add block
      </button>

      {preview.length > 0 && (
        <details className="card preview">
          <summary>Preview the {preview.length} intervals this runs as</summary>
          <ol className="preview-list">
            {preview.map((interval) => (
              <li key={interval.index} className={interval.kind === 'rest' ? 'rest' : ''}>
                <span className="preview-name">{interval.name}</span>
                <span className="muted small">
                  {interval.duration_seconds != null
                    ? `${interval.duration_seconds}s`
                    : repsDisplay(interval)}
                  {interval.intensity && ` · ${interval.intensity}`}
                  {weightDisplay(interval) && ` @ ${weightDisplay(interval)}`}
                  {interval.set_count > 1 && ` · set ${interval.set_index} of ${interval.set_count}`}
                  {interval.block_round_count > 1 &&
                    ` · round ${interval.block_round} of ${interval.block_round_count}`}
                </span>
              </li>
            ))}
          </ol>
        </details>
      )}
    </section>
  );
}
