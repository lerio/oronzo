import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { createExercise, deleteExercise, listExercises } from '../lib/api';
import { MUSCLE_GROUPS, exerciseSummary, type Exercise, type StepMode } from '../lib/types';

export default function Exercises() {
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');

  const [name, setName] = useState('');
  const [muscleGroup, setMuscleGroup] = useState<string>('chest');
  const [mode, setMode] = useState<StepMode>('reps');
  const [twoSides, setTwoSides] = useState(false);

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
        default_mode: mode,
        has_two_sides: twoSides,
      });
      setExercises((current) => [...current, created].sort((a, b) => a.name.localeCompare(b.name)));
      setName('');
      setTwoSides(false);
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

  // Memoised because the filter box drives this on every keystroke, and the old form also
  // lower-cased every exercise's name once per element per render to test it.
  //
  // There is no seeded/custom split any more: the library was deleted in `0010`, so every row
  // here is the user's own.
  const filtered = useMemo(() => {
    const needle = filter.trim().toLowerCase();
    if (!needle) return exercises;
    return exercises.filter((e) => e.name.toLowerCase().includes(needle));
  }, [exercises, filter]);

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
        <select value={mode} onChange={(e) => setMode(e.target.value as StepMode)}>
          <option value="reps">reps</option>
          <option value="time">time</option>
        </select>
        <label className="inline-field" title="Performed once per side — left, then right">
          <input
            type="checkbox"
            checked={twoSides}
            onChange={(e) => setTwoSides(e.target.checked)}
          />
          <span>2 sides</span>
        </label>
        <button className="primary" type="submit">
          Add
        </button>
      </form>

      <h2 className="section-title">Your exercises ({filtered.length})</h2>
      {filtered.length === 0 ? (
        <p className="muted small">
          {exercises.length === 0
            ? 'Nothing here yet — add your first exercise above.'
            : `No exercise matches “${filter.trim()}”.`}
        </p>
      ) : (
        <ul className="plan-list">
          {filtered.map((exercise) => (
            <li key={exercise.id} className="card plan-row">
              <div className="plan-main">
                <span className="plan-name">{exercise.name}</span>
                <span className="muted small">{exerciseSummary(exercise)}</span>
              </div>
              <button className="link-btn danger" onClick={() => void onDelete(exercise)}>
                Delete
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
