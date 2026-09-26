import { useState, type FormEvent } from 'react';
import { signIn } from '../auth';
import { errorMessage } from '../lib/errors';

/**
 * There is no sign-up flow on purpose. This app has exactly one user, created by hand in
 * the Supabase dashboard — which also sidesteps the free tier's 2-emails-per-hour limit,
 * since no confirmation or password-reset mail is ever needed.
 */
export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await signIn(email, password);
    } catch (err) {
      setError(errorMessage(err, 'Sign in failed'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="centered">
      <form className="card login-card" onSubmit={onSubmit}>
        <h1 className="login-title">Oronzo</h1>
        <p className="muted small">Sign in to build and manage workout plans.</p>

        <label className="field">
          <span>Email</span>
          <input
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
        </label>

        <label className="field">
          <span>Password</span>
          <input
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>

        {error && <p className="error">{error}</p>}

        <button className="primary" type="submit" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
