import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { getPlan, listExercises, savePlan } from '../lib/api';
import {
  estimateSeconds,
  flattenPlan,
  formatDuration,
  repsDisplay,
  weightDisplay,
  type Exercise,
  type Plan,
  type PlanBlock,
  type PlanStep,
  type StepMode,
} from '../lib/types';

const blankPlan = (): Plan => ({ id: '', name: '', notes: null, blocks: [] });

function stepFromExercise(exercise: Exercise | undefined): PlanStep {
  const isTime = exercise?.default_mode === 'time';
  return {
    exercise_id: exercise?.id ?? null,
    position: 0,
    kind: 'exercise',
    label: null,
    mode: exercise?.default_mode ?? 'reps',
    duration_seconds: isTime ? (exercise?.default_duration_seconds ?? 45) : null,
    reps: isTime ? null : (exercise?.default_reps ?? 10),
    target_weight_kg: null,
    rest_after_seconds: null,
    notes: null,
  };
}

function restStep(): PlanStep {
  return {
    exercise_id: null,
    position: 0,
    kind: 'rest',
    label: null,
    mode: 'time',
    duration_seconds: 60,
    reps: null,
    target_weight_kg: null,
    rest_after_seconds: null,
    notes: null,
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
  if (step.kind === 'exercise' && !step.exercise_id) return 'Pick an exercise';
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
        const loaded = await listExercises();
        if (cancelled) return;
        setExercises(loaded);

        if (isNew) {
          setPlan(blankPlan());
        } else {
          const found = await getPlan(id!);
          if (!cancelled) setPlan(found ?? blankPlan());
        }
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Could not load plan');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id, isNew]);

  const exerciseNames = useMemo(
    () => new Map(exercises.map((exercise) => [exercise.id, exercise.name])),
    [exercises],
  );

  const preview = useMemo(
    () => (plan ? flattenPlan(plan, exerciseNames) : []),
    [plan, exerciseNames],
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

  function changeExercise(blockIndex: number, stepIndex: number, exerciseId: string) {
    const exercise = exercises.find((candidate) => candidate.id === exerciseId);
    updateStep(blockIndex, stepIndex, stepFromExercise(exercise));
  }

  function changeMode(blockIndex: number, stepIndex: number, mode: StepMode, current: PlanStep) {
    updateStep(blockIndex, stepIndex, {
      mode,
      duration_seconds: mode === 'time' ? (current.duration_seconds ?? 45) : null,
      reps: mode === 'reps' ? (current.reps ?? 10) : null,
    });
  }

  const problems = plan.blocks.flatMap((block) =>
    block.steps.map(stepProblem).filter((problem): problem is string => problem !== null),
  );

  async function onSave() {
    if (!plan) return;
    if (!plan.name.trim()) {
      setError('Give the plan a name first.');
      return;
    }
    if (problems.length > 0) {
      setError(`Fix ${problems.length} step${problems.length === 1 ? '' : 's'} before saving.`);
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

  const totalSeconds = estimateSeconds(preview);

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
          {totalSeconds > 0 && ` · ~${formatDuration(totalSeconds)} of timed work`}
        </span>
        <span className="muted small">
          A block's <em>rounds</em> repeats everything inside it — that is how sets and circuits are
          expressed.
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
                type="number"
                min={1}
                value={block.rounds}
                onChange={(e) => updateBlock(blockIndex, { rounds: Math.max(1, Number(e.target.value) || 1) })}
              />
            </label>
            <label className="inline-field">
              <span>rest between rounds (s)</span>
              <input
                type="number"
                min={0}
                placeholder="none"
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
            const problem = stepProblem(step);
            return (
              <div key={stepIndex} className={problem ? 'step-row invalid' : 'step-row'}>
                <span className="step-index">{stepIndex + 1}</span>

                <select
                  value={step.kind}
                  onChange={(e) =>
                    e.target.value === 'rest'
                      ? updateStep(blockIndex, stepIndex, restStep())
                      : updateStep(blockIndex, stepIndex, stepFromExercise(exercises[0]))
                  }
                >
                  <option value="exercise">exercise</option>
                  <option value="rest">rest</option>
                </select>

                {step.kind === 'exercise' ? (
                  <select
                    value={step.exercise_id ?? ''}
                    onChange={(e) => changeExercise(blockIndex, stepIndex, e.target.value)}
                  >
                    <option value="">— pick —</option>
                    {exercises.map((exercise) => (
                      <option key={exercise.id} value={exercise.id}>
                        {exercise.name}
                      </option>
                    ))}
                  </select>
                ) : (
                  <input
                    placeholder="Break"
                    value={step.label ?? ''}
                    onChange={(e) => updateStep(blockIndex, stepIndex, { label: e.target.value || null })}
                  />
                )}

                {step.kind === 'exercise' && (
                  <select
                    value={step.mode}
                    onChange={(e) => changeMode(blockIndex, stepIndex, e.target.value as StepMode, step)}
                  >
                    <option value="reps">reps</option>
                    <option value="time">time</option>
                  </select>
                )}

                {step.mode === 'time' ? (
                  <label className="inline-field">
                    <span>sec</span>
                    <input
                      type="number"
                      min={1}
                      value={step.duration_seconds ?? ''}
                      onChange={(e) =>
                        updateStep(blockIndex, stepIndex, { duration_seconds: Number(e.target.value) || null })
                      }
                    />
                  </label>
                ) : (
                  <label className="inline-field">
                    <span>reps</span>
                    <input
                      type="number"
                      min={1}
                      value={step.reps ?? ''}
                      onChange={(e) =>
                        updateStep(blockIndex, stepIndex, { reps: Number(e.target.value) || null })
                      }
                    />
                  </label>
                )}

                {step.kind === 'exercise' && (
                  <label className="inline-field">
                    <span>kg</span>
                    <input
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
                )}

                <label className="inline-field">
                  <span>rest after (s)</span>
                  <input
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
            <button className="link-btn" onClick={() => addStep(blockIndex, stepFromExercise(exercises[0]))}>
              + exercise
            </button>
            <button className="link-btn" onClick={() => addStep(blockIndex, restStep())}>
              + rest
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
                  {weightDisplay(interval) && ` @ ${weightDisplay(interval)}`}
                  {' · '}
                  round {interval.round_index}
                </span>
              </li>
            ))}
          </ol>
        </details>
      )}
    </section>
  );
}
