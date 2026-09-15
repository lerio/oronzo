import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react';
import type { Exercise } from '../lib/types';

interface ExercisePickerProps {
  exercises: Exercise[];
  value: string | null;
  onChange: (exerciseId: string) => void;
}

/**
 * A searchable replacement for a plain `<select>`.
 *
 * With ~115 seeded exercises plus whatever you add, scrolling a native dropdown to find
 * one is tedious — and on a narrow field the names are truncated anyway. This filters as
 * you type and matches on muscle group and equipment too, so "cable back" finds the cable
 * rows without knowing what any of them are called.
 *
 * Deliberately hand-rolled rather than pulling in a combobox library: it is the only
 * control of its kind here, and it is ~120 lines.
 */
export default function ExercisePicker({ exercises, value, onChange }: ExercisePickerProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [highlight, setHighlight] = useState(0);

  const rootRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  const selected = exercises.find((exercise) => exercise.id === value) ?? null;

  const matches = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return exercises;
    return exercises.filter((exercise) =>
      `${exercise.name} ${exercise.muscle_group} ${exercise.equipment}`
        .toLowerCase()
        .includes(needle),
    );
  }, [exercises, query]);

  // On open: clear the previous search and put the cursor in the box.
  useEffect(() => {
    if (!open) return;
    setQuery('');
    setHighlight(0);
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
    onChange(exercise.id);
    setOpen(false);
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

      {open && (
        <ul className="picker-list" role="listbox">
          {matches.length === 0 ? (
            <li className="picker-empty muted small">No exercise matches “{query.trim()}”.</li>
          ) : (
            matches.map((exercise, index) => (
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
                  <span className="picker-meta">
                    {exercise.muscle_group.replace('_', ' ')} · {exercise.equipment}
                  </span>
                </button>
              </li>
            ))
          )}
        </ul>
      )}
    </div>
  );
}
