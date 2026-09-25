import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { deletePlan, listExercises, listPlans } from '../lib/api';
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
  const navigate = useNavigate();

  useEffect(() => {
    Promise.all([listPlans(), listExercises()])
      .then(([p, e]) => {
        setPlans(p);
        setExercises(e);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  async function onDelete(plan: Plan) {
    if (!confirm(`Delete "${plan.name}"? Past sessions keep their record.`)) return;
    try {
      await deletePlan(plan.id);
      setPlans((current) => current.filter((p) => p.id !== plan.id));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Delete failed');
    }
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
  if (error) return <p className="error">{error}</p>;

  return (
    <section>
      <div className="page-head">
        <h1>Plans</h1>
        <button className="primary" onClick={() => navigate('/plans/new')}>
          New plan
        </button>
      </div>

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
            <li key={plan.id} className="card plan-row">
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
