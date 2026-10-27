import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { deleteWorkout, listExercises, listPlans, listWorkouts, reorderWorkouts } from '../lib/api';
import { errorMessage } from '../lib/errors';
import {
  WEEKDAYS,
  estimateWorkoutDuration,
  flattenWorkout,
  formatDuration,
  preferredTimeLabel,
  type Exercise,
  type WeekPlan,
  type Workout,
} from '../lib/types';

/** The reusable sessions, and the order they are picked in. Scheduling lives under Plans. */
export default function Workouts() {
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [plans, setPlans] = useState<WeekPlan[]>([]);
  const [plansUnavailable, setPlansUnavailable] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  /** The row being dragged, so it can be dimmed — and so hover can tell "moving" from "not". */
  const [draggingId, setDraggingId] = useState<string | null>(null);
  /** The order as it was when the drag began, to decide whether anything changed. */
  const orderBeforeDrag = useRef<string[] | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    Promise.all([
      listWorkouts(),
      listExercises(),
      // The membership badges are secondary: a plan fetch failure must not hide the library.
      listPlans().catch(() => {
        setPlansUnavailable(true);
        setError('Could not load plan memberships; showing workouts without them.');
        return [] as WeekPlan[];
      }),
    ])
      .then(([w, e, p]) => {
        setWorkouts(w);
        setExercises(e);
        setPlans(p);
      })
      .catch((err) => setError(errorMessage(err, 'Could not load workouts')))
      .finally(() => setLoading(false));
  }, []);

  async function onDelete(workout: Workout) {
    const planCount = plans.filter((plan) =>
      plan.slots.some((slot) => slot.workout_id === workout.id),
    ).length;
    const scheduled = plansUnavailable
      ? ' Plan memberships could not be checked; deleting also removes any schedule entries.'
      : planCount === 0
        ? ''
        : ` It is scheduled in ${planCount} plan${planCount === 1 ? '' : 's'} and will be removed from them.`;
    if (!confirm(`Delete "${workout.name}"?${scheduled} Past sessions keep their record.`)) return;

    try {
      await deleteWorkout(workout.id);
      setWorkouts((current) => current.filter((w) => w.id !== workout.id));
    } catch (err) {
      setError(errorMessage(err, 'Delete failed'));
    }
  }

  // ---------------------------------------------------------------------------
  // Reordering, by dragging the grip.
  //
  // The array order IS the render order, so a drag is a local reorder and the database is told
  // afterwards — the row follows the cursor instead of waiting on a round trip.
  // ---------------------------------------------------------------------------

  function onDragStart(event: DragEvent, workout: Workout) {
    setDraggingId(workout.id);
    orderBeforeDrag.current = workouts.map((w) => w.id);
    event.dataTransfer.effectAllowed = 'move';
    // Firefox refuses to start a drag that carries no data.
    event.dataTransfer.setData('text/plain', workout.id);
  }

  /** Moving the dragged row *to the hovered row's index* — not a swap, so the rest keep order. */
  function onDragEnterRow(event: DragEvent, overId: string) {
    event.preventDefault();
    if (!draggingId || draggingId === overId) return;

    setWorkouts((current) => {
      const from = current.findIndex((w) => w.id === draggingId);
      const to = current.findIndex((w) => w.id === overId);
      if (from === -1 || to === -1 || from === to) return current;
      const next = [...current];
      const [moved] = next.splice(from, 1);
      next.splice(to, 0, moved);
      return next;
    });
  }

  /**
   * Persist on release, and only if something actually moved.
   *
   * `workouts` is read from the closure rather than a ref: every drag-enter re-renders, and React
   * flushes a discrete event's state before the next one, so this handler is the latest render's
   * by the time the drag ends. A drag that ends where it started costs no request at all.
   */
  function onDragEnd() {
    const before = orderBeforeDrag.current;
    orderBeforeDrag.current = null;
    setDraggingId(null);
    if (!before) return;

    const after = workouts.map((w) => w.id);
    if (after.join() === before.join()) return;

    void (async () => {
      try {
        await reorderWorkouts(after);
      } catch (err) {
        // Put the rows back where they were, so the screen does not claim an order the database
        // never took. By id, because a workout may have been deleted in another tab meanwhile.
        setWorkouts((current) => {
          const byId = new Map(current.map((w) => [w.id, w]));
          return before.map((id) => byId.get(id)).filter((w): w is Workout => w !== undefined);
        });
        setError(errorMessage(err, 'Could not save the new order'));
      }
    })();
  }

  // One Map and one set of derived rows per fetch, rather than per render.
  const exercisesById = useMemo(() => new Map(exercises.map((e) => [e.id, e])), [exercises]);

  const rows = useMemo(
    () =>
      workouts.map((workout) => {
        const intervals = flattenWorkout(workout, exercisesById);
        const scheduled = plans.flatMap((plan) => {
          const days = plan.slots
            .filter((slot) => slot.workout_id === workout.id)
            .map((slot) => WEEKDAYS.find((day) => day.value === slot.weekday)?.label ?? '');
          return days.length > 0 ? [`${days.join(', ')} · ${plan.name}`] : [];
        });

        return {
          workout,
          blocks: workout.blocks.length,
          intervals: intervals.length,
          duration: estimateWorkoutDuration(workout, intervals, exercisesById),
          scheduled: plansUnavailable
            ? 'Plan memberships unavailable'
            : scheduled.length > 0
              ? scheduled.join('; ')
              : 'Not in a plan',
        };
      }),
    [workouts, exercisesById, plans, plansUnavailable],
  );

  if (loading) return <p className="muted">Loading workouts…</p>;
  // A load failure is the whole page. A failure *after* loading — a delete, a reorder — leaves the
  // list on screen and reports itself above it, which is what the banner below is for.
  if (error && workouts.length === 0) return <p className="error">{error}</p>;

  return (
    <section>
      <div className="page-head">
        <div>
          <h1>Workouts</h1>
          <p className="muted small">
            Reusable sessions. Schedule them into a week under Plans.
          </p>
        </div>
        <button className="primary" onClick={() => navigate('/workouts/new')}>
          New workout
        </button>
      </div>

      {error && <p className="error">{error}</p>}

      {workouts.length === 0 ? (
        <div className="card empty">
          <p>No workouts yet.</p>
          <p className="muted small">
            Build one here, then schedule it into a weekly plan.
          </p>
        </div>
      ) : (
        <ul className="plan-list">
          {rows.map(({ workout, blocks, intervals, duration, scheduled }) => (
            <li
              key={workout.id}
              className={draggingId === workout.id ? 'card plan-row dragging' : 'card plan-row'}
              onDragEnter={(event) => onDragEnterRow(event, workout.id)}
              onDragOver={(event) => {
                // Required: without this the browser refuses the drop, and `dropEffect` is what
                // makes the cursor say "move" rather than "no entry".
                event.preventDefault();
                event.dataTransfer.dropEffect = 'move';
              }}
              onDrop={(event) => event.preventDefault()}
            >
              {/* The only draggable thing in the row, so a drag never starts from a link — and
                  hidden from assistive tech, which cannot use it and is offered the plans board
                  instead. */}
              <span
                className="plan-grip"
                draggable
                onDragStart={(event) => onDragStart(event, workout)}
                onDragEnd={onDragEnd}
                title="Drag to reorder"
                aria-hidden="true"
              >
                ⠿
              </span>
              <div className="plan-main">
                <Link className="plan-name" to={`/workouts/${workout.id}`}>
                  {workout.name}
                </Link>
                <span className="muted small">
                  <span className="pill">{preferredTimeLabel(workout.preferred_time)}</span>{' '}
                  {blocks} block{blocks === 1 ? '' : 's'} · {intervals} interval{intervals === 1 ? '' : 's'}
                  {duration.seconds > 0 &&
                    ` · ${duration.isEstimate ? '~' : ''}${formatDuration(duration.seconds)}`}
                </span>
                <span className="muted small">{scheduled}</span>
              </div>
              <div className="plan-actions">
                <Link className="link-btn" to={`/workouts/${workout.id}`}>
                  Edit
                </Link>
                <button className="link-btn danger" onClick={() => void onDelete(workout)}>
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
