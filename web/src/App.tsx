import { Suspense, lazy } from 'react';
import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { signOut, useAuth } from './auth';
import Login from './routes/Login';

// The signed-in routes load on navigation, not on first paint.
//
// They used to be imported eagerly, which put all of them — and the whole Supabase client, the
// largest thing in the bundle, along with the `realtime-js` it bundles and this app never calls —
// on the critical path of the sign-in screen. Split, the login screen ships without any of it, and
// what is behind it arrives per tab.
const WeekPlans = lazy(() => import('./routes/WeekPlans'));
const WeekPlanEditor = lazy(() => import('./routes/WeekPlanEditor'));
const Workouts = lazy(() => import('./routes/Workouts'));
const WorkoutEditor = lazy(() => import('./routes/WorkoutEditor'));
const Exercises = lazy(() => import('./routes/Exercises'));
const History = lazy(() => import('./routes/History'));

export default function App() {
  const { session, loading } = useAuth();
  const location = useLocation();

  if (loading) return <div className="centered muted">Loading…</div>;
  if (!session) return <Login />;

  const tabs = [
    { to: '/plans', label: 'Plans' },
    { to: '/workouts', label: 'Workouts' },
    { to: '/exercises', label: 'Exercises' },
    { to: '/history', label: 'History' },
  ];

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark">Oronzo</span>
          <span className="brand-sub">workout builder</span>
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
            <Route path="/plans" element={<WeekPlans />} />
            {/* Old bookmarks: /plans/new is no longer a form; the list creates and navigates. */}
            <Route path="/plans/new" element={<Navigate to="/plans" replace />} />
            <Route path="/plans/:id" element={<WeekPlanEditor />} />
            <Route path="/workouts" element={<Workouts />} />
            <Route path="/workouts/new" element={<WorkoutEditor />} />
            <Route path="/workouts/:id" element={<WorkoutEditor />} />
            <Route path="/exercises" element={<Exercises />} />
            <Route path="/history" element={<History />} />
            <Route path="*" element={<Navigate to="/plans" replace />} />
          </Routes>
        </Suspense>
      </main>
    </div>
  );
}
