import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { createPlan, deletePlan, listExercises, listPlans, listWorkouts } from '../lib/api';
import { errorMessage } from '../lib/errors';
import {
  WEEKDAYS,
  estimateWorkoutDuration,
  flattenWorkout,
  formatDuration,
  type Exercise,
  type WeekPlan,
  type Workout,
} from '../lib/types';

/** The weekly templates. A workout can appear in more than one, and on more than one day. */
export default function WeekPlans() {
  const [plans, setPlans] = useState<WeekPlan[]>([]);
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [newName, setNewName] = useState('My week');
  const [busy, setBusy] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    Promise.all([listPlans(), listWorkouts(), listExercises()])
      .then(([p, w, e]) => {
        setPlans(p);
        setWorkouts(w);
        setExercises(e);
      })
      .catch((err) => setError(errorMessage(err, 'Could not load plans')))
      .finally(() => setLoading(false));
  }, []);

  async function onCreate() {
    const name = newName.trim() || 'My week';
    setBusy(true);
    setError(null);
    try {
      const plan = await createPlan(name);
      navigate(`/plans/${plan.id}?new=1`);
    } catch (err) {
      setError(errorMessage(err, 'Could not create the plan'));
      setBusy(false);
    }
  }

  async function onDelete(plan: WeekPlan) {
    if (!confirm(`Delete the weekly schedule "${plan.name}"? The workouts stay in your library.`)) {
      return;
    }
    try {
      await deletePlan(plan.id);
      setPlans((current) => current.filter((p) => p.id !== plan.id));
    } catch (err) {
      setError(errorMessage(err, 'Delete failed'));
    }
  }

  const exercisesById = useMemo(() => new Map(exercises.map((e) => [e.id, e])), [exercises]);

  const rows = useMemo(() => {
    const durationById = new Map(
      workouts.map((workout) => {
        const intervals = flattenWorkout(workout, exercisesById);
        return [workout.id, estimateWorkoutDuration(workout, intervals, exercisesById)];
      }),
    );

    return plans.map((plan) => {
      const days = new Set(plan.slots.map((slot) => slot.weekday));
      const seconds = plan.slots.reduce(
        (total, slot) => total + (durationById.get(slot.workout_id)?.seconds ?? 0),
        0,
      );
      // If any workout in the week is estimated, the week's total is too.
      const estimated = plan.slots.some((slot) => durationById.get(slot.workout_id)?.isEstimate);
      return { plan, sessions: plan.slots.length, days, seconds, estimated };
    });
  }, [plans, workouts, exercisesById]);

  if (loading) return <p className="muted">Loading plans…</p>;
  if (error && plans.length === 0) return <p className="error">{error}</p>;

  return (
    <section>
      <div className="page-head">
        <div>
          <h1>Plans</h1>
          <p className="muted small">
            Weekly templates. A workout can appear in more than one plan and on more than one day.
          </p>
        </div>
        {creating ? (
          <div className="head-actions">
            <input
              autoFocus
              value={newName}
              placeholder="My week"
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') void onCreate();
                if (e.key === 'Escape') setCreating(false);
              }}
            />
            <button className="primary" onClick={() => void onCreate()} disabled={busy}>
              {busy ? 'Creating…' : 'Create'}
            </button>
            <button className="link-btn" onClick={() => setCreating(false)}>
              Cancel
            </button>
          </div>
        ) : (
          <button className="primary" onClick={() => setCreating(true)}>
            New plan
          </button>
        )}
      </div>

      {error && <p className="error">{error}</p>}

      {plans.length === 0 ? (
        <div className="card empty">
          <p>No weekly plans yet.</p>
          <p className="muted small">
            Create one, then drag workouts into its days.
          </p>
        </div>
      ) : (
        <ul className="plan-list">
          {rows.map(({ plan, sessions, days, seconds, estimated }) => (
            <li key={plan.id} className="card plan-row">
              <div className="plan-main">
                <Link className="plan-name" to={`/plans/${plan.id}`}>
                  {plan.name}
                </Link>
                <span className="muted small">
                  {sessions} session{sessions === 1 ? '' : 's'} · {days.size} day{days.size === 1 ? '' : 's'}
                  {seconds > 0 && ` · ${estimated ? '~' : ''}${formatDuration(seconds)}`}
                </span>
                <div className="mini-week" aria-hidden="true">
                  {WEEKDAYS.map((day) => (
                    <span key={day.value} className={days.has(day.value) ? 'mini-day on' : 'mini-day'}>
                      {day.label.slice(0, 2)}
                    </span>
                  ))}
                </div>
              </div>
              <div className="plan-actions">
                <Link className="link-btn" to={`/plans/${plan.id}`}>
                  Open
                </Link>
                <button className="link-btn danger" onClick={() => void onDelete(plan)}>
                  Delete
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
