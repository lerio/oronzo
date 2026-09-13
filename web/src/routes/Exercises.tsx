import { useEffect, useState, type FormEvent } from 'react';
import { createExercise, deleteExercise, listExercises } from '../lib/api';
import { EQUIPMENT, MUSCLE_GROUPS, type Exercise, type StepMode } from '../lib/types';

export default function Exercises() {
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');

  const [name, setName] = useState('');
  const [muscleGroup, setMuscleGroup] = useState<string>('chest');
  const [equipment, setEquipment] = useState<string>('barbell');
  const [mode, setMode] = useState<StepMode>('reps');

  useEffect(() => {
    listExercises()
      .then(setExercises)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  async function onCreate(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const created = await createExercise({
        name: name.trim(),
        muscle_group: muscleGroup,
        equipment,
        default_mode: mode,
        default_duration_seconds: mode === 'time' ? 45 : null,
        default_reps: mode === 'reps' ? 10 : null,
      });
      setExercises((current) => [...current, created].sort((a, b) => a.name.localeCompare(b.name)));
      setName('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create exercise');
    }
  }

  async function onDelete(exercise: Exercise) {
    if (!confirm(`Delete "${exercise.name}"?`)) return;
    setError(null);
    try {
      await deleteExercise(exercise.id);
      setExercises((current) => current.filter((e) => e.id !== exercise.id));
    } catch (err) {
      // A RESTRICT foreign key means this exercise is referenced by a plan step. That is
      // deliberate — silently gutting a plan would be worse — so say so plainly.
      setError(
        err instanceof Error && /violates foreign key|restrict/i.test(err.message)
          ? `"${exercise.name}" is still used by a plan. Remove it from that plan first.`
          : err instanceof Error
            ? err.message
            : 'Delete failed',
      );
    }
  }

  const visible = exercises.filter((e) => e.name.toLowerCase().includes(filter.toLowerCase()));
  const seeded = visible.filter((e) => e.user_id === null);
  const custom = visible.filter((e) => e.user_id !== null);

  if (loading) return <p className="muted">Loading exercises…</p>;

  return (
    <section>
      <div className="page-head">
        <h1>Exercises</h1>
        <input
          className="search"
          placeholder="Filter…"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
      </div>

      {error && <p className="error">{error}</p>}

      <form className="card inline-form" onSubmit={onCreate}>
        <strong>Add exercise</strong>
        <input placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} required />
        <select value={muscleGroup} onChange={(e) => setMuscleGroup(e.target.value)}>
          {MUSCLE_GROUPS.map((g) => (
            <option key={g} value={g}>
              {g.replace('_', ' ')}
            </option>
          ))}
        </select>
        <select value={equipment} onChange={(e) => setEquipment(e.target.value)}>
          {EQUIPMENT.map((g) => (
            <option key={g} value={g}>
              {g}
            </option>
          ))}
        </select>
        <select value={mode} onChange={(e) => setMode(e.target.value as StepMode)}>
          <option value="reps">reps</option>
          <option value="time">time</option>
        </select>
        <button className="primary" type="submit">
          Add
        </button>
      </form>

      <h2 className="section-title">Yours ({custom.length})</h2>
      {custom.length === 0 ? (
        <p className="muted small">Nothing custom yet — the seeded library below covers the basics.</p>
      ) : (
        <ul className="plan-list">
          {custom.map((exercise) => (
            <li key={exercise.id} className="card plan-row">
              <div className="plan-main">
                <span className="plan-name">{exercise.name}</span>
                <span className="muted small">
                  {exercise.muscle_group.replace('_', ' ')} · {exercise.equipment} ·{' '}
                  {exercise.default_mode}
                </span>
              </div>
              <button className="link-btn danger" onClick={() => void onDelete(exercise)}>
                Delete
              </button>
            </li>
          ))}
        </ul>
      )}

      <h2 className="section-title">Library ({seeded.length})</h2>
      <ul className="plan-list compact">
        {seeded.map((exercise) => (
          <li key={exercise.id} className="card plan-row">
            <div className="plan-main">
              <span className="plan-name">{exercise.name}</span>
              <span className="muted small">
                {exercise.muscle_group.replace('_', ' ')} · {exercise.equipment} ·{' '}
                {exercise.default_mode}
              </span>
            </div>
            <span className="pill">built-in</span>
          </li>
        ))}
      </ul>
    </section>
  );
}
