import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import ExercisePicker from '../components/ExercisePicker';
import { getPlan, listExercises, savePlan } from '../lib/api';
import {
  INTENSITIES,
  estimatePlanDuration,
  flattenPlan,
  formatDuration,
  repsDisplay,
  weightDisplay,
  type Exercise,
  type Intensity,
  type Plan,
  type PlanBlock,
  type PlanStep,
} from '../lib/types';

const blankPlan = (): Plan => ({ id: '', name: '', blocks: [] });

function stepFromExercise(exercise?: Exercise): PlanStep {
  const isTime = exercise?.default_mode === 'time';
  return {
    exercise_id: exercise?.id ?? null,
    position: 0,
    label: null,
    sets: 1,
    mode: exercise?.default_mode ?? 'reps',
    duration_seconds: isTime ? (exercise?.default_duration_seconds ?? 45) : null,
    reps: isTime ? null : (exercise?.default_reps ?? 10),
    target_weight_kg: null,
    rest_after_seconds: null,
    // Optional, so a freshly-picked timed step starts with none and the row offers "—". The
    // builder is where the effort is chosen; an exercise cannot dictate it, because a HIIT block
    // runs the same movement hard and easy.
    intensity: null,
  };
}

/** Re-index positions from array order — positions must always be contiguous per parent. */
function normalize(plan: Plan): Plan {
  return {
    ...plan,
    blocks: plan.blocks.map((block, blockIndex) => ({
      ...block,
      position: blockIndex,
      steps: block.steps.map((step, stepIndex) => ({ ...step, position: stepIndex })),
    })),
  };
}

/**
 * Mirrors the DB's plan_steps_shape constraint, so problems surface before a failed save
 * rather than as a raw Postgres error.
 */
function stepProblem(step: PlanStep): string | null {
  if (!step.exercise_id) return 'Pick an exercise';
  if (step.mode === 'time' && !step.duration_seconds) return 'Needs a duration';
  if (step.mode === 'reps' && !step.reps) return 'Needs a rep target';
  return null;
}

export default function PlanEditor() {
  const { id } = useParams();
  const navigate = useNavigate();
  const isNew = !id;

  const [plan, setPlan] = useState<Plan | null>(null);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedAt, setSavedAt] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        // In parallel: the two requests do not depend on each other, and awaiting them in turn
        // made opening an existing plan two round trips deep instead of one. `setExercises`
        // happens once both are in, exactly as before.
        const [loaded, found] = await Promise.all([
          listExercises(),
          isNew ? Promise.resolve(null) : getPlan(id!),
        ]);
        if (cancelled) return;
        setExercises(loaded);
        setPlan(isNew ? blankPlan() : (found ?? blankPlan()));
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Could not load plan');
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
    () => (plan ? flattenPlan(plan, exercisesById) : []),
    [plan, exercisesById],
  );

  // `exercisesById` is listed as well as `preview`, rather than relied on through it: the rep
  // half of the estimate reads the map directly, so a changed map with an unchanged preview
  // would otherwise leave the total stale.
  const duration = useMemo(
    () => (plan ? estimatePlanDuration(plan, preview, exercisesById) : { seconds: 0, isEstimate: false }),
    [plan, preview, exercisesById],
  );

  // Per step, in the plan's own shape, so each row below can index straight into it. Flattened it
  // would lose which step each problem belongs to, and the row would have to work it out again —
  // which is what it did, so every keystroke walked all the steps twice.
  const stepProblems = useMemo(
    () => plan?.blocks.map((block) => block.steps.map(stepProblem)) ?? [],
    [plan],
  );
  const problemCount = stepProblems.reduce(
    (total, block) => total + block.filter((problem) => problem !== null).length,
    0,
  );

  if (!plan) return <p className="muted">{error ?? 'Loading…'}</p>;

  const mutate = (fn: (draft: Plan) => Plan) => setPlan((current) => (current ? normalize(fn(current)) : current));

  const updateBlock = (blockIndex: number, patch: Partial<PlanBlock>) =>
    mutate((draft) => ({
      ...draft,
      blocks: draft.blocks.map((block, i) => (i === blockIndex ? { ...block, ...patch } : block)),
    }));

  const updateStep = (blockIndex: number, stepIndex: number, patch: Partial<PlanStep>) =>
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

  const addStep = (blockIndex: number, step: PlanStep) =>
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
    if (!plan) return;
    if (!plan.name.trim()) {
      setError('Give the plan a name first.');
      return;
    }
    if (problemCount > 0) {
      setError(`Fix ${problemCount} step${problemCount === 1 ? '' : 's'} before saving.`);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const savedId = await savePlan(plan);
      setSavedAt(new Date().toLocaleTimeString());
      if (isNew) navigate(`/plans/${savedId}`, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  }

  // Derived once per plan change rather than on every render. This was the worst of the three
  // memos put in: `stepProblem` ran over every step for `problems`, and then ran again per row
  // inside the JSX below — so a single keystroke in any field walked all the steps twice.
  return (
    <section>
      <div className="page-head">
        <h1>{isNew ? 'New plan' : 'Edit plan'}</h1>
        <div className="head-actions">
          {savedAt && <span className="muted small">Saved {savedAt}</span>}
          <button className="primary" onClick={() => void onSave()} disabled={saving}>
            {saving ? 'Saving…' : 'Save plan'}
          </button>
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      <div className="card">
        <label className="field">
          <span>Name</span>
          <input
            value={plan.name}
            placeholder="e.g. Push A"
            onChange={(e) => mutate((draft) => ({ ...draft, name: e.target.value }))}
          />
        </label>
      </div>

      <div className="summary-bar">
        <span>
          {plan.blocks.length} block{plan.blocks.length === 1 ? '' : 's'} · {preview.length} interval
          {preview.length === 1 ? '' : 's'}
          {/* No longer "of timed work": the figure now includes the reps, as the phone's does. */}
          {duration.seconds > 0 &&
            ` · ~${formatDuration(duration.seconds)}${duration.isEstimate ? ' plus reps' : ''}`}
        </span>
        <span className="muted small">
          An exercise's <em>sets</em> is its set count; a block's <em>rounds</em> repeats the whole
          group — that is how circuits are expressed.
        </span>
      </div>

      {plan.blocks.map((block, blockIndex) => (
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
                    rep target and a load, or a duration — is the exercise's mode, so before one
                    is picked there is nothing here that would not be a guess. The row says
                    "Pick an exercise" below and waits. */}
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

                    {/* The step's mode is the exercise's — there is no select for it any more.
                        Picking an exercise re-derives the whole step through `stepFromExercise`,
                        so what this row shows is whatever that mode actually has: a rep target
                        and a load, or a duration. */}
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

                        {/* Offered for a timed step only, and optional within one: the effort is
                            what a HIIT interval is prescribed as, while a strength hold is just a
                            hold. "—" is the same empty placeholder the numeric fields use, and it
                            means the interval says nothing about effort while it runs. */}
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
                once the exercise — and so the mode those fields belong to — is chosen. */}
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
