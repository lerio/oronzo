import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import {
  addPlanWorkout,
  getPlan,
  listExercises,
  listWorkouts,
  movePlanWorkout,
  removePlanWorkout,
  renamePlan,
} from '../lib/api';
import { errorMessage } from '../lib/errors';
import {
  WEEKDAYS,
  compareWorkoutsByTimeThenName,
  estimateWorkoutDuration,
  flattenWorkout,
  formatDuration,
  preferredTimeLabel,
  type Exercise,
  type WeekPlan,
  type Weekday,
  type Workout,
} from '../lib/types';

type Dragging = { workoutId: string; fromWeekday: Weekday | null };

function dayLabel(day: Weekday): string {
  return WEEKDAYS.find((entry) => entry.value === day)?.label ?? '';
}

/**
 * The week board: a shelf of workouts over seven day columns.
 *
 * Every scheduling action is one `plan_workouts` row — add, remove or move — and saves
 * immediately. There is no Save button because there is no whole-week payload to lose; a failed
 * action is put back and offered again.
 *
 * The week is a template, not a calendar: there are no dates anywhere on this screen.
 */
export default function WeekPlanEditor() {
  const { id } = useParams();
  const [params] = useSearchParams();
  const navigate = useNavigate();

  const [plan, setPlan] = useState<WeekPlan | null>(null);
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const [pending, setPending] = useState(0);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [retryAction, setRetryAction] = useState<{ run: () => void } | null>(null);
  const lastSavedName = useRef('');

  const [search, setSearch] = useState('');
  const [dragging, setDragging] = useState<Dragging | null>(null);
  const [dragOver, setDragOver] = useState<Weekday | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [loaded, loadedWorkouts, loadedExercises] = await Promise.all([
          getPlan(id!),
          listWorkouts(),
          listExercises(),
        ]);
        if (cancelled) return;
        setWorkouts(loadedWorkouts);
        setExercises(loadedExercises);
        if (loaded) {
          setPlan(loaded);
          lastSavedName.current = loaded.name;
        } else {
          setError('This plan no longer exists.');
        }
      } catch (err) {
        if (!cancelled) setError(errorMessage(err, 'Could not load the plan'));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  const exercisesById = useMemo(() => new Map(exercises.map((e) => [e.id, e])), [exercises]);
  const workoutsById = useMemo(() => new Map(workouts.map((w) => [w.id, w])), [workouts]);
  const durations = useMemo(
    () =>
      new Map(
        workouts.map((workout) => {
          const intervals = flattenWorkout(workout, exercisesById);
          return [workout.id, estimateWorkoutDuration(workout, intervals, exercisesById)];
        }),
      ),
    [workouts, exercisesById],
  );

  function cardsFor(day: Weekday): Workout[] {
    return (plan?.slots ?? [])
      .filter((slot) => slot.weekday === day)
      .map((slot) => workoutsById.get(slot.workout_id))
      .filter((workout): workout is Workout => workout !== undefined)
      .sort(compareWorkoutsByTimeThenName);
  }

  function durationLabel(workout: Workout): string {
    const estimate = durations.get(workout.id);
    if (!estimate || estimate.seconds <= 0) return '—';
    return `${estimate.isEstimate ? '~' : ''}${formatDuration(estimate.seconds)}`;
  }

  // ---------------------------------------------------------------------------
  // Schedule writes. Optimistic, one row at a time, rolled back on failure.
  // ---------------------------------------------------------------------------

  async function persist(next: WeekPlan, action: () => Promise<void>, rollback: WeekPlan) {
    setPlan(next);
    setPending((count) => count + 1);
    setSaveError(null);
    setRetryAction(null);
    try {
      await action();
    } catch (err) {
      setPlan(rollback);
      setSaveError(errorMessage(err, 'Could not save the schedule'));
      setRetryAction({
        run: () => {
          void persist(next, action, rollback);
        },
      });
    } finally {
      setPending((count) => count - 1);
    }
  }

  function add(workoutId: string, weekday: Weekday) {
    if (!plan) return;
    if (plan.slots.some((slot) => slot.workout_id === workoutId && slot.weekday === weekday)) return;
    const next = { ...plan, slots: [...plan.slots, { workout_id: workoutId, weekday }] };
    void persist(next, () => addPlanWorkout(plan.id, workoutId, weekday), plan);
  }

  function remove(workoutId: string, weekday: Weekday) {
    if (!plan) return;
    const next = {
      ...plan,
      slots: plan.slots.filter(
        (slot) => !(slot.workout_id === workoutId && slot.weekday === weekday),
      ),
    };
    void persist(next, () => removePlanWorkout(plan.id, workoutId, weekday), plan);
  }

  function move(workoutId: string, from: Weekday, to: Weekday) {
    if (!plan || from === to) return;
    const targetHasIt = plan.slots.some(
      (slot) => slot.workout_id === workoutId && slot.weekday === to,
    );
    const slots = plan.slots.filter(
      (slot) => !(slot.workout_id === workoutId && slot.weekday === from),
    );
    if (!targetHasIt) slots.push({ workout_id: workoutId, weekday: to });
    const next = { ...plan, slots };
    void persist(next, () => movePlanWorkout(plan.id, workoutId, from, to), plan);
  }

  // ---------------------------------------------------------------------------
  // Drag and drop. The picker in each day header is the keyboard/touch path.
  // ---------------------------------------------------------------------------

  function onDragStart(event: DragEvent, workoutId: string, fromWeekday: Weekday | null) {
    const payload: Dragging = { workoutId, fromWeekday };
    setDragging(payload);
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', JSON.stringify(payload));
  }

  function onDragEnd() {
    setDragging(null);
    setDragOver(null);
  }

  function onDrop(event: DragEvent, weekday: Weekday) {
    event.preventDefault();
    setDragOver(null);
    setDragging(null);

    const raw = event.dataTransfer.getData('text/plain');
    if (!raw) return;
    let payload: Partial<Dragging>;
    try {
      payload = JSON.parse(raw);
    } catch {
      return;
    }
    if (typeof payload.workoutId !== 'string') return;

    const from = typeof payload.fromWeekday === 'number'
      && payload.fromWeekday >= 1
      && payload.fromWeekday <= 7
      ? (payload.fromWeekday as Weekday)
      : null;

    if (from == null) add(payload.workoutId, weekday);
    else move(payload.workoutId, from, weekday);
  }

  // ---------------------------------------------------------------------------
  // The plan name. Saved on blur/Enter; the schedule actions never send it.
  // ---------------------------------------------------------------------------

  async function saveName(name: string, before: string) {
    if (!plan) return;
    setPlan((current) => (current ? { ...current, name } : current));
    setPending((count) => count + 1);
    setSaveError(null);
    setRetryAction(null);
    try {
      await renamePlan(plan.id, name);
      lastSavedName.current = name;
    } catch (err) {
      setPlan((current) => (current ? { ...current, name: before } : current));
      setSaveError(errorMessage(err, 'Could not rename the plan'));
    } finally {
      setPending((count) => count - 1);
    }
  }

  function commitName() {
    if (!plan) return;
    const trimmed = plan.name.trim();
    if (!trimmed) {
      setPlan({ ...plan, name: lastSavedName.current });
      return;
    }
    if (trimmed === lastSavedName.current) {
      if (plan.name !== trimmed) setPlan({ ...plan, name: trimmed });
      return;
    }
    void saveName(trimmed, lastSavedName.current);
  }

  // ---------------------------------------------------------------------------

  if (loading) return <p className="muted">Loading plan…</p>;
  if (!plan) {
    return (
      <section>
        <p className="error">{error ?? 'Plan not found.'}</p>
        <Link className="link-btn" to="/plans">
          ← Plans
        </Link>
      </section>
    );
  }

  const searchText = search.trim().toLowerCase();
  const shelf = workouts.filter(
    (workout) => searchText === '' || workout.name.toLowerCase().includes(searchText),
  );

  return (
    <section>
      <div className="page-head">
        <div>
          <Link className="link-btn" to="/plans">
            ← Plans
          </Link>
          <input
            className="week-plan-name"
            aria-label="Plan name"
            value={plan.name}
            autoFocus={params.get('new') === '1'}
            onChange={(event) => setPlan({ ...plan, name: event.target.value })}
            onBlur={commitName}
            onKeyDown={(event) => {
              if (event.key === 'Enter') event.currentTarget.blur();
            }}
          />
          <p className="muted small">A weekly template — no dates.</p>
        </div>

        {saveError ? (
          <span className="error small" role="status" aria-live="polite">
            {retryAction ? (
              <>
                Couldn't save.{' '}
                <button className="link-btn" onClick={() => retryAction.run()}>
                  Retry
                </button>
              </>
            ) : (
              saveError
            )}
          </span>
        ) : (
          <span className="muted small" role="status" aria-live="polite">
            {pending > 0 ? 'Saving…' : 'All changes saved'}
          </span>
        )}
      </div>

      {saveError && retryAction && <p className="error">{saveError}</p>}

      <div className="week-shelf">
        <div className="week-shelf-head">
          <strong>Workouts</strong>
          <input
            placeholder="Search…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            aria-label="Search workouts"
          />
          <Link className="link-btn" to={`/workouts/new?plan=${plan.id}`}>
            + New workout
          </Link>
        </div>

        <div className="week-shelf-cards">
          {shelf.map((workout) => {
            const days = plan.slots
              .filter((slot) => slot.workout_id === workout.id)
              .map((slot) => dayLabel(slot.weekday));

            return (
              <div
                key={workout.id}
                className={
                  dragging?.workoutId === workout.id && dragging.fromWeekday == null
                    ? 'week-card shelf dragging'
                    : 'week-card shelf'
                }
                draggable
                onDragStart={(event) => onDragStart(event, workout.id, null)}
                onDragEnd={onDragEnd}
              >
                <div className="week-card-head">
                  <span className="time-chip">{preferredTimeLabel(workout.preferred_time)}</span>
                </div>
                <Link className="week-card-name" draggable={false} to={`/workouts/${workout.id}`}>
                  {workout.name}
                </Link>
                <span className="muted small">
                  {durationLabel(workout)}
                  {days.length > 0 && ` · ${days.join(', ')}`}
                </span>
              </div>
            );
          })}

          {workouts.length === 0 && (
            <p className="muted small">
              No workouts yet.{' '}
              <Link className="link-btn" to={`/workouts/new?plan=${plan.id}`}>
                Create one
              </Link>
              .
            </p>
          )}
        </div>
      </div>

      {plan.slots.length === 0 && (
        <p className="muted small">Drag a workout into a day, or use a day's + picker.</p>
      )}

      <div className="week-grid">
        {WEEKDAYS.map((day) => {
          const cards = cardsFor(day.value);
          const seconds = cards.reduce(
            (total, workout) => total + (durations.get(workout.id)?.seconds ?? 0),
            0,
          );
          const estimated = cards.some((workout) => durations.get(workout.id)?.isEstimate);
          const available = workouts.filter(
            (workout) =>
              !plan.slots.some(
                (slot) => slot.weekday === day.value && slot.workout_id === workout.id,
              ),
          );

          return (
            <div
              key={day.value}
              className={dragOver === day.value ? 'week-day drop-target' : 'week-day'}
              onDragOver={(event) => {
                event.preventDefault();
                event.dataTransfer.dropEffect = 'move';
                setDragOver(day.value);
              }}
              onDrop={(event) => onDrop(event, day.value)}
            >
              <div className="week-day-head">
                <span>{day.label}</span>
                <span className="muted small">
                  {cards.length > 0 ? cards.length : ''}
                  {seconds > 0 && ` ${estimated ? '~' : ''}${formatDuration(seconds)}`}
                </span>
                <select
                  className="week-add"
                  value=""
                  aria-label={`Add a workout to ${day.label}`}
                  onChange={(event) => {
                    const value = event.target.value;
                    if (value === '__new__') {
                      navigate(`/workouts/new?plan=${plan.id}&weekday=${day.value}`);
                    } else if (value) {
                      add(value, day.value);
                    }
                  }}
                >
                  <option value="">+</option>
                  {available.map((workout) => (
                    <option key={workout.id} value={workout.id}>
                      {workout.name}
                    </option>
                  ))}
                  <option value="__new__">New workout for {day.label}…</option>
                </select>
              </div>

              <div className="week-day-cards">
                {cards.length === 0 && <p className="week-day-empty">Drop a workout here</p>}

                {cards.map((workout) => (
                  <div
                    key={workout.id}
                    className={
                      dragging?.workoutId === workout.id && dragging.fromWeekday === day.value
                        ? 'week-card dragging'
                        : 'week-card'
                    }
                    draggable
                    onDragStart={(event) => onDragStart(event, workout.id, day.value)}
                    onDragEnd={onDragEnd}
                  >
                    <div className="week-card-head">
                      <span className="time-chip">{preferredTimeLabel(workout.preferred_time)}</span>
                      <button
                        className="icon-btn danger"
                        aria-label={`Remove ${workout.name} from ${day.label}`}
                        onClick={() => remove(workout.id, day.value)}
                      >
                        ×
                      </button>
                    </div>
                    <Link className="week-card-name" draggable={false} to={`/workouts/${workout.id}`}>
                      {workout.name}
                    </Link>
                    <span className="muted small">{durationLabel(workout)}</span>
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
