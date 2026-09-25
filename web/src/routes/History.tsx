import { useEffect, useState } from 'react';
import { deleteSession, listSessions, type SessionSummary } from '../lib/api';
import { formatDuration } from '../lib/types';

export default function History() {
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  // Kept apart from `error`, which blanks the page: a delete that fails should leave the list
  // it failed to change on screen.
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    listSessions()
      .then(setSessions)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  async function onDelete(session: SessionSummary) {
    const when = new Date(session.started_at).toLocaleString();
    // An in-progress session is one the phone still has open. Deleting it here does not stop the
    // workout — it only leaves the finish with nothing to write to — so say so rather than let
    // the wording imply the wrist will notice.
    const running = session.status === 'in_progress' ? ' It is still running on your phone.' : '';
    if (!confirm(`Delete the "${session.plan_name}" session from ${when}?${running}`)) return;

    setDeleteError(null);
    try {
      await deleteSession(session.id);
      setSessions((current) => current.filter((s) => s.id !== session.id));
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Delete failed');
    }
  }

  if (loading) return <p className="muted">Loading history…</p>;
  if (error) return <p className="error">{error}</p>;

  return (
    <section>
      <div className="page-head">
        <h1>History</h1>
      </div>

      {deleteError && <p className="error">{deleteError}</p>}

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
              <div className="plan-actions">
                <span className={session.status === 'completed' ? 'pill good' : 'pill'}>
                  {session.status.replace('_', ' ')}
                </span>
                <button className="link-btn danger" onClick={() => void onDelete(session)}>
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
