import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { deletePlan, listExercises, listPlans } from '../lib/api';
import { estimateSeconds, flattenPlan, formatDuration, type Exercise, type Plan } from '../lib/types';

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

  const names = new Map(exercises.map((e) => [e.id, e.name]));

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
          {plans.map((plan) => {
            const intervals = flattenPlan(plan, names);
            const seconds = estimateSeconds(intervals);
            return (
              <li key={plan.id} className="card plan-row">
                <div className="plan-main">
                  <Link className="plan-name" to={`/plans/${plan.id}`}>
                    {plan.name}
                  </Link>
                  <span className="muted small">
                    {plan.blocks.length} block{plan.blocks.length === 1 ? '' : 's'} ·{' '}
                    {intervals.length} step{intervals.length === 1 ? '' : 's'}
                    {seconds > 0 && ` · ~${formatDuration(seconds)} timed`}
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
            );
          })}
        </ul>
      )}
    </section>
  );
}
