import { useEffect, useMemo, useRef, useState, type FormEvent, type KeyboardEvent } from 'react';
import { createExercise } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { MUSCLE_GROUPS, exerciseSummary, type Exercise, type StepMode } from '../lib/types';

interface ExercisePickerProps {
  exercises: Exercise[];
  value: string | null;
  /**
   * Fired with the chosen exercise — the object, not its id. The caller has no way to resolve a
   * just-created one by id: it was made inside this component, and reaches the caller's list in
   * the same batch of state updates that this callback is part of.
   */
  onChange: (exercise: Exercise) => void;
  /**
   * Called with an exercise created from inside the picker. The caller has to fold it into the
   * list it renders from, or the step that now points at it would read as unpicked.
   */
  onCreated?: (exercise: Exercise) => void;
}

/**
 * A searchable replacement for a plain `<select>`, which can also create what it cannot find.
 *
 * A native dropdown is tedious to scroll to a name, and on a narrow field it truncates the
 * names anyway. This filters as you type and matches on muscle group and the exercise's own
 * default too, so "back" finds the back rows without knowing what any of them are called.
 *
 * When nothing matches, the dead end is where the authoring actually is: you are naming an
 * exercise that does not exist yet. So instead of sending you to another tab, the panel offers
 * to create it — the search text becomes the name, and the same three fields the Exercises page
 * asks for are the whole form. Saving selects it, which is what makes the step's own fields
 * appear.
 *
 * Deliberately hand-rolled rather than pulling in a combobox library: it is the only
 * control of its kind here, and it is ~190 lines.
 */
export default function ExercisePicker({
  exercises,
  value,
  onChange,
  onCreated,
}: ExercisePickerProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [highlight, setHighlight] = useState(0);

  // The create form, swapped in over the results when the search comes up empty.
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState('');
  const [muscleGroup, setMuscleGroup] = useState<string>('chest');
  const [mode, setMode] = useState<StepMode>('reps');
  const [twoSides, setTwoSides] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const rootRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  const selected = exercises.find((exercise) => exercise.id === value) ?? null;

  const needle = query.trim().toLowerCase();

  const matches = useMemo(() => {
    if (!needle) return exercises;
    return exercises.filter((exercise) =>
      `${exercise.name} ${exerciseSummary(exercise)}`.toLowerCase().includes(needle),
    );
  }, [exercises, needle]);

  /**
   * Offered whenever the box holds something you do not already have: an exact name means there
   * is nothing to add (and `exercises_user_name_key` would refuse it anyway), and an empty box
   * means you are browsing what you have, not naming something new.
   */
  const exactMatch = exercises.some(
    (exercise) => exercise.name.trim().toLowerCase() === needle,
  );
  const canAddNew = needle !== '' && !exactMatch;

  // On open: clear the previous search and put the cursor in the box.
  useEffect(() => {
    if (!open) return;
    setQuery('');
    setHighlight(0);
    setCreating(false);
    setError(null);
    searchRef.current?.focus();
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('pointerdown', onPointerDown);
    return () => document.removeEventListener('pointerdown', onPointerDown);
  }, [open]);

  // Narrowing the query can shorten the list out from under the highlight. Clamped on read
  // rather than corrected in an effect: storing the fix would cost a second render and go
  // stale again the moment the list changes.
  const activeIndex = Math.min(highlight, Math.max(0, matches.length - 1));

  function choose(exercise: Exercise) {
    onChange(exercise);
    setOpen(false);
  }

  function startCreating() {
    setName(query.trim());
    setError(null);
    setCreating(true);
  }

  async function onCreate(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const created = await createExercise({
        name: name.trim(),
        muscle_group: muscleGroup,
        default_mode: mode,
        has_two_sides: twoSides,
      });
      // Both updates land in one render: the caller adds it to the list this component looks
      // `value` up in, so the picker shows the new name rather than falling back to "— pick —".
      onCreated?.(created);
      choose(created);
    } catch (err) {
      setError(errorMessage(err, 'Could not create exercise'));
    } finally {
      setSaving(false);
    }
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    switch (event.key) {
      // Both move from `activeIndex`, not from the raw state, so arrowing continues from
      // the row the user can actually see highlighted.
      case 'ArrowDown':
        event.preventDefault();
        setHighlight(Math.min(activeIndex + 1, matches.length - 1));
        break;
      case 'ArrowUp':
        event.preventDefault();
        setHighlight(Math.max(activeIndex - 1, 0));
        break;
      case 'Enter': {
        event.preventDefault();
        const match = matches[activeIndex];
        if (match) choose(match);
        break;
      }
      case 'Escape':
        event.preventDefault();
        setOpen(false);
        break;
      default:
        break;
    }
  }

  return (
    <div className="picker" ref={rootRef}>
      {open ? (
        <input
          ref={searchRef}
          className="picker-search"
          placeholder="Search exercises…"
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
            setHighlight(0);
          }}
          onKeyDown={onKeyDown}
        />
      ) : (
        <button type="button" className="picker-button" onClick={() => setOpen(true)}>
          <span className={selected ? 'picker-name' : 'picker-name muted'}>
            {selected ? selected.name : '— pick —'}
          </span>
          <span className="picker-caret" aria-hidden="true">
            ▾
          </span>
        </button>
      )}

      {open &&
        (creating ? (
          <form
            className="picker-list picker-new"
            onSubmit={onCreate}
            // Escape backs out of the form rather than the whole panel: a half-typed name is
            // worth more than the search that led here.
            onKeyDown={(event) => {
              if (event.key !== 'Escape') return;
              event.preventDefault();
              setCreating(false);
              setError(null);
            }}
          >
            <input
              className="picker-search"
              placeholder="Name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              autoFocus
              required
            />
            <div className="picker-new-fields">
              <select value={muscleGroup} onChange={(event) => setMuscleGroup(event.target.value)}>
                {MUSCLE_GROUPS.map((group) => (
                  <option key={group} value={group}>
                    {group.replace('_', ' ')}
                  </option>
                ))}
              </select>
              <select value={mode} onChange={(event) => setMode(event.target.value as StepMode)}>
                <option value="reps">reps</option>
                <option value="time">time</option>
              </select>
            </div>
            <label className="inline-field" title="Performed once per side — left, then right">
              <input
                type="checkbox"
                checked={twoSides}
                onChange={(event) => setTwoSides(event.target.checked)}
              />
              <span>2 sides</span>
            </label>
            <div className="picker-new-fields">
              <button className="primary" type="submit" disabled={saving}>
                {saving ? 'Saving…' : 'Save'}
              </button>
            </div>
            {error && <p className="error small">{error}</p>}
          </form>
        ) : (
          <ul className="picker-list" role="listbox">
            {matches.length === 0 && (
              <li className="picker-empty muted small">
                {exercises.length === 0
                  ? 'No exercises yet.'
                  : `No exercise matches “${query.trim()}”.`}
              </li>
            )}

            {matches.map((exercise, index) => (
              <li key={exercise.id}>
                <button
                  type="button"
                  role="option"
                  aria-selected={index === activeIndex}
                  className={index === activeIndex ? 'picker-option active' : 'picker-option'}
                  onMouseEnter={() => setHighlight(index)}
                  onClick={() => choose(exercise)}
                >
                  <span className="picker-name">{exercise.name}</span>
                  <span className="picker-meta">{exerciseSummary(exercise)}</span>
                </button>
              </li>
            ))}

            {canAddNew && (
              <li className="picker-new-row">
                <button type="button" className="link-btn" onClick={startCreating}>
                  Add New
                </button>
              </li>
            )}
          </ul>
        ))}
    </div>
  );
}
