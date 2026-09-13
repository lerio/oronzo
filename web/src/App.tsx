import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { signOut, useAuth } from './auth';
import Login from './routes/Login';
import Plans from './routes/Plans';
import PlanEditor from './routes/PlanEditor';
import Exercises from './routes/Exercises';
import History from './routes/History';

export default function App() {
  const { session, loading } = useAuth();
  const location = useLocation();

  if (loading) return <div className="centered muted">Loading…</div>;
  if (!session) return <Login />;

  const tabs = [
    { to: '/plans', label: 'Plans' },
    { to: '/exercises', label: 'Exercises' },
    { to: '/history', label: 'History' },
  ];

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark">Oronzo</span>
          <span className="brand-sub">plan builder</span>
        </div>
        <nav className="tabs">
          {tabs.map((tab) => (
            <Link
              key={tab.to}
              to={tab.to}
              className={location.pathname.startsWith(tab.to) ? 'tab active' : 'tab'}
            >
              {tab.label}
            </Link>
          ))}
        </nav>
        <button className="link-btn" onClick={() => void signOut()}>
          Sign out
        </button>
      </header>

      <main className="content">
        <Routes>
          <Route path="/" element={<Navigate to="/plans" replace />} />
          <Route path="/plans" element={<Plans />} />
          <Route path="/plans/new" element={<PlanEditor />} />
          <Route path="/plans/:id" element={<PlanEditor />} />
          <Route path="/exercises" element={<Exercises />} />
          <Route path="/history" element={<History />} />
          <Route path="*" element={<Navigate to="/plans" replace />} />
        </Routes>
      </main>
    </div>
  );
}
