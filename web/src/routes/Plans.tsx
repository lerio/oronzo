import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { deletePlan, listExercises, listPlans, reorderPlans } from '../lib/api';
import { errorMessage } from '../lib/errors';
import {
  estimatePlanDuration,
  flattenPlan,
  formatDuration,
  type Exercise,
  type Plan,
} from '../lib/types';

export default function Plans() {
  const [plans, setPlans] = useState<Plan[]>([]);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  /** The row being dragged, so it can be dimmed — and so hover can tell "moving" from "not". */
  const [draggingId, setDraggingId] = useState<string | null>(null);
  /** The order as it was when the drag began, to decide whether anything changed. */
  const orderBeforeDrag = useRef<string[] | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    Promise.all([listPlans(), listExercises()])
      .then(([p, e]) => {
        setPlans(p);
        setExercises(e);
      })
      .catch((err) => setError(errorMessage(err, 'Could not load plans')))
      .finally(() => setLoading(false));
  }, []);

  async function onDelete(plan: Plan) {
    if (!confirm(`Delete "${plan.name}"? Past sessions keep their record.`)) return;
    try {
      await deletePlan(plan.id);
      setPlans((current) => current.filter((p) => p.id !== plan.id));
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

  function onDragStart(event: DragEvent, plan: Plan) {
    setDraggingId(plan.id);
    orderBeforeDrag.current = plans.map((p) => p.id);
    event.dataTransfer.effectAllowed = 'move';
    // Firefox refuses to start a drag that carries no data.
    event.dataTransfer.setData('text/plain', plan.id);
  }

  /** Moving the dragged row *to the hovered row's index* — not a swap, so the rest keep order. */
  function onDragEnterRow(event: DragEvent, overId: string) {
    event.preventDefault();
    if (!draggingId || draggingId === overId) return;

    setPlans((current) => {
      const from = current.findIndex((p) => p.id === draggingId);
      const to = current.findIndex((p) => p.id === overId);
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
   * `plans` is read from the closure rather than a ref: every drag-enter re-renders, and React
   * flushes a discrete event's state before the next one, so this handler is the latest render's
   * by the time the drag ends. A drag that ends where it started costs no request at all.
   */
  function onDragEnd() {
    const before = orderBeforeDrag.current;
    orderBeforeDrag.current = null;
    setDraggingId(null);
    if (!before) return;

    const after = plans.map((p) => p.id);
    if (after.join() === before.join()) return;

    void (async () => {
      try {
        await reorderPlans(after);
      } catch (err) {
        // Put the rows back where they were, so the screen does not claim an order the database
        // never took. By id, because a plan may have been deleted in another tab meanwhile.
        setPlans((current) => {
          const byId = new Map(current.map((p) => [p.id, p]));
          return before.map((id) => byId.get(id)).filter((p): p is Plan => p !== undefined);
        });
        setError(errorMessage(err, 'Could not save the new order'));
      }
    })();
  }

  // One Map and one set of derived rows per fetch, rather than per render.
  //
  // The map below used to rebuild `names` on every render and re-flatten and re-estimate every
  // plan inside the loop — so a list of eight plans re-derived the same eight arrays each time
  // anything on the page re-rendered, including a delete's confirmation state. The work is a
  // function of the plans and the exercise names, and neither changes while you are looking at it.
  const exercisesById = useMemo(() => new Map(exercises.map((e) => [e.id, e])), [exercises]);

  const rows = useMemo(
    () =>
      plans.map((plan) => {
        const intervals = flattenPlan(plan, exercisesById);
        return {
          plan,
          blocks: plan.blocks.length,
          steps: intervals.length,
          duration: estimatePlanDuration(plan, intervals, exercisesById),
        };
      }),
    [plans, exercisesById],
  );

  if (loading) return <p className="muted">Loading plans…</p>;
  // A load failure is the whole page. A failure *after* loading — a delete, a reorder — leaves the
  // list on screen and reports itself above it, which is what the banner below is for.
  if (error && plans.length === 0) return <p className="error">{error}</p>;

  return (
    <section>
      <div className="page-head">
        <h1>Plans</h1>
        <button className="primary" onClick={() => navigate('/plans/new')}>
          New plan
        </button>
      </div>

      {error && <p className="error">{error}</p>}

      {plans.length === 0 ? (
        <div className="card empty">
          <p>No plans yet.</p>
          <p className="muted small">
            Build one here, then pick it on the iPhone and run it on your Watch.
          </p>
        </div>
      ) : (
        <ul className="plan-list">
          {rows.map(({ plan, blocks, steps, duration }) => (
            <li
              key={plan.id}
              className={draggingId === plan.id ? 'card plan-row dragging' : 'card plan-row'}
              onDragEnter={(event) => onDragEnterRow(event, plan.id)}
              onDragOver={(event) => {
                // Required: without this the browser refuses the drop, and `dropEffect` is what
                // makes the cursor say "move" rather than "no entry".
                event.preventDefault();
                event.dataTransfer.dropEffect = 'move';
              }}
              onDrop={(event) => event.preventDefault()}
            >
              {/* The only draggable thing in the row, so a drag never starts from a link — and
                  hidden from assistive tech, which cannot use it and is offered nothing else. */}
              <span
                className="plan-grip"
                draggable
                onDragStart={(event) => onDragStart(event, plan)}
                onDragEnd={onDragEnd}
                title="Drag to reorder"
                aria-hidden="true"
              >
                ⠿
              </span>
              <div className="plan-main">
                <Link className="plan-name" to={`/plans/${plan.id}`}>
                  {plan.name}
                </Link>
                <span className="muted small">
                  {blocks} block{blocks === 1 ? '' : 's'} · {steps} step{steps === 1 ? '' : 's'}
                  {/* No longer "timed": the figure includes the rep work, so naming which half
                      it counted was both wrong and the reason it disagreed with the phone. */}
                  {duration.seconds > 0 && ` · ~${formatDuration(duration.seconds)}`}
                </span>
              </div>
              <div className="plan-actions">
                <Link className="link-btn" to={`/plans/${plan.id}`}>
                  Edit
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
