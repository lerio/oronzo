import { Suspense, lazy } from 'react';
import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { signOut, useAuth } from './auth';
import Login from './routes/Login';

// The four signed-in routes load on navigation, not on first paint.
//
// They used to be imported eagerly, which put all of them — and the whole Supabase client, the
// largest thing in the bundle, along with the `realtime-js` it bundles and this app never calls —
// on the critical path of the sign-in screen. Split, the login screen ships without any of it, and
// what is behind it arrives per tab.
const Plans = lazy(() => import('./routes/Plans'));
const PlanEditor = lazy(() => import('./routes/PlanEditor'));
const Exercises = lazy(() => import('./routes/Exercises'));
const History = lazy(() => import('./routes/History'));

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
        {/* The top bar and the tabs stay mounted across a navigation, so only the panel swaps —
            the same shape as the `loading` line above, which keeps the shell from flashing. */}
        <Suspense fallback={<div className="centered muted">Loading…</div>}>
          <Routes>
            <Route path="/" element={<Navigate to="/plans" replace />} />
            <Route path="/plans" element={<Plans />} />
            <Route path="/plans/new" element={<PlanEditor />} />
            <Route path="/plans/:id" element={<PlanEditor />} />
            <Route path="/exercises" element={<Exercises />} />
            <Route path="/history" element={<History />} />
            <Route path="*" element={<Navigate to="/plans" replace />} />
          </Routes>
        </Suspense>
      </main>
    </div>
  );
}
