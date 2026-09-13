import { useEffect, useState } from 'react';
import { listSessions, type SessionSummary } from '../lib/api';
import { formatDuration } from '../lib/types';

export default function History() {
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    listSessions()
      .then(setSessions)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <p className="muted">Loading history…</p>;
  if (error) return <p className="error">{error}</p>;

  return (
    <section>
      <div className="page-head">
        <h1>History</h1>
      </div>

      {sessions.length === 0 ? (
        <div className="card empty">
          <p>No sessions yet.</p>
          <p className="muted small">Finish a workout on the iPhone and it appears here.</p>
        </div>
      ) : (
        <ul className="plan-list">
          {sessions.map((session) => (
            <li key={session.id} className="card plan-row">
              <div className="plan-main">
                <span className="plan-name">{session.plan_name}</span>
                <span className="muted small">
                  {new Date(session.started_at).toLocaleString()} · {session.step_count} steps
                  {session.total_duration_seconds != null &&
                    ` · ${formatDuration(session.total_duration_seconds)}`}
                </span>
              </div>
              <span className={session.status === 'completed' ? 'pill good' : 'pill'}>
                {session.status.replace('_', ' ')}
              </span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
