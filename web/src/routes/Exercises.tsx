import { useEffect, useMemo, useState, type FormEvent } from 'react';
import {
  createExercise,
  deleteExercise,
  listExercises,
  plansUsingExercise,
  updateExercise,
} from '../lib/api';
import { errorMessage, isForeignKeyViolation, isUniqueViolation } from '../lib/errors';
import {
  MUSCLE_GROUPS,
  exerciseSummary,
  sidesOf,
  type Exercise,
  type Sides,
} from '../lib/types';

/**
 * Why the exercise cannot go yet, naming the plans that hold it.
 *
 * The refusal is a RESTRICT foreign key: `plan_steps.exercise_id` cannot be left orphaned, so a
 * plan step still points at this exercise. That is deliberate — silently gutting a plan would be
 * worse — and it is also the whole rule, since an exercise no plan uses deletes normally. It
 * arrives as a 409, reported by `isForeignKeyViolation`.
 *
 * Naming them is the point of the message: the refusal is correct, but "a plan" is not something
 * you can go and act on. Best-effort — if the lookup itself fails the sentence is still true,
 * just less immediately useful.
 */
async function inUseMessage(exercise: Exercise): Promise<string> {
  const fallback = `"${exercise.name}" is still used by a plan. Remove it from that plan first.`;
  try {
    const plans = await plansUsingExercise(exercise.id);
    if (plans.length === 0) return fallback;
    const where =
      plans.length === 1
        ? `the plan "${plans[0]}"`
        : `these plans: ${plans.map((name) => `"${name}"`).join(', ')}`;
    return `"${exercise.name}" is used by ${where}. Remove it there first.`;
  } catch {
    return fallback;
  }
}

/**
 * The order `listExercises` asks the server for — group first, then name — applied locally, so a
 * row a save just moved lands where a reload would put it.
 *
 * The two used to disagree: adding an exercise sorted by name alone, which nobody could see while
 * the grouped order was only what a *fetch* produced. An edit that changes the group makes them
 * differ on screen, so both paths now use this.
 */
function byGroupThenName(a: Exercise, b: Exercise): number {
  return a.muscle_group.localeCompare(b.muscle_group) || a.name.localeCompare(b.name);
}

/**
 * The groups on offer, plus whatever this row actually carries.
 *
 * `MUSCLE_GROUPS` constrains nothing already stored — `exercises.muscle_group` is plain text with
 * no check constraint — so a row can hold a word the list no longer offers. Without this the
 * `<select>` would render its *first* option over a row that is not that, and the panel would be
 * lying about the one field it is asking the user to confirm.
 */
function groupOptions(stored: string): readonly string[] {
  return (MUSCLE_GROUPS as readonly string[]).includes(stored)
    ? MUSCLE_GROUPS
    : [stored, ...MUSCLE_GROUPS];
}

/**
 * What changing how an exercise is performed will do to the plans that use it — said while the
 * change is being staged, and only then.
 *
 * **It is not a rename, which is why it used to be read-only here.** `has_two_sides` doubles every
 * interval of every plan using this exercise (a set becomes left, then right) and taking it away
 * halves them again; `alternates_sides` keeps one interval per set but changes what the step's rep
 * count means — the total for both sides rather than the number for each. Silently rewriting the
 * shape of a workout from a panel that otherwise edits a label is the thing this line exists to
 * prevent, and the copy names the consequence rather than asking "are you sure?".
 */
function sidesChangeNote(exercise: Exercise, sides: Sides): string | null {
  if (sides === sidesOf(exercise)) return null;
  const notes: Record<Sides, string> = {
    none: '1 side stops the left/right split, halving the intervals of every plan using this exercise.',
    two: '2 sides makes every set of every plan using this exercise two intervals — left, then right.',
    alternate:
      'Alternating keeps one interval per set, and reads the step’s reps as the total for both sides.',
  };
  return notes[sides];
}

/** What is known about which plans hold an exercise: the names, or why they are not here. */
type Usage = string[] | 'loading' | 'unavailable';

/**
 * "Used in N plans", or what to say instead while that is unknown.
 *
 * Named rather than counted, for the reason `inUseMessage` gives: a bare number is not something
 * you can go and act on. `unavailable` is deliberately not `0` — "not used in any plan" is a
 * claim, and it is the one wrong claim that would make someone think a delete will succeed when
 * this page is about to refuse it.
 */
function usageLine(state: Usage | undefined): string {
  if (state === undefined || state === 'loading') return 'Checking which plans use this…';
  if (state === 'unavailable') return 'Could not check which plans use this.';
  if (state.length === 0) return 'Not used in any plan.';
  const where = state.map((plan) => `"${plan}"`).join(', ');
  return `Used in ${state.length} plan${state.length === 1 ? '' : 's'}: ${where}`;
}

export default function Exercises() {
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');

  const [name, setName] = useState('');
  const [muscleGroup, setMuscleGroup] = useState<string>('chest');
  /** One of three — see `Sides` for why the impossible pair is not constructible here. */
  const [sides, setSides] = useState<Sides>('none');

  /**
   * The open editor: which exercise, and the three fields it owns. `null` when none is open.
   *
   * One slot rather than an id plus a set of draft fields, because a draft that can outlive its
   * row is a draft that can be saved onto a different one. The id *is* the panel's identity —
   * which is also what makes filtering the row out and back in safe.
   */
  const [draft, setDraft] = useState<{
    id: string;
    name: string;
    muscle_group: string;
    sides: Sides;
  } | null>(null);
  /**
   * The panel's own failure, kept apart from `error` — which is the banner for a list that failed
   * to load. A refused rename must leave every other row exactly as it was, and must not put a red
   * line above the page about a request the user did not make. The same split, and the same
   * reason, as `History`'s `deleteError`.
   */
  const [editError, setEditError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  /**
   * Which plans hold an exercise, asked the first time its panel is opened and kept for the life
   * of the page. Keyed by id rather than held as "the open one": there is no cancellation anywhere
   * in this app, and keying is what stops a slow answer landing under the exercise the user has
   * since moved to.
   */
  const [usage, setUsage] = useState<Record<string, Usage>>({});

  useEffect(() => {
    listExercises()
      .then(setExercises)
      .catch((err) => setError(errorMessage(err, 'Could not load exercises')))
      .finally(() => setLoading(false));
  }, []);

  async function onCreate(event: FormEvent) {
    event.preventDefault();
    setError(null);
    try {
      const created = await createExercise({
        name: name.trim(),
        muscle_group: muscleGroup,
        has_two_sides: sides === 'two',
        alternates_sides: sides === 'alternate',
      });
      setExercises((current) => [...current, created].sort(byGroupThenName));
      setName('');
      setSides('none');
    } catch (err) {
      setError(errorMessage(err, 'Could not create exercise'));
    }
  }

  async function onDelete(exercise: Exercise) {
    if (!confirm(`Delete "${exercise.name}"?`)) return;
    setError(null);
    try {
      await deleteExercise(exercise.id);
      setExercises((current) => current.filter((e) => e.id !== exercise.id));
      // The panel cannot outlive its row: its draft names an id that is gone, and a form left
      // open over a row that is not there has nothing to save onto.
      setDraft((current) => (current?.id === exercise.id ? null : current));
    } catch (err) {
      if (isForeignKeyViolation(err)) {
        setError(await inUseMessage(exercise));
        return;
      }
      setError(errorMessage(err, 'Delete failed'));
    }
  }

  // ---------------------------------------------------------------------------
  // Editing, in a panel that opens inside the row it edits.
  // ---------------------------------------------------------------------------

  function closeEditor() {
    setDraft(null);
    setEditError(null);
  }

  function openEditor(exercise: Exercise) {
    if (draft?.id === exercise.id) {
      closeEditor();
      return;
    }
    setDraft({
      id: exercise.id,
      name: exercise.name,
      muscle_group: exercise.muscle_group,
      sides: sidesOf(exercise),
    });
    setEditError(null);
    loadUsage(exercise.id);
  }

  /**
   * Asks which plans hold this exercise, once.
   *
   * Deliberately not on page load: `plansUsingExercise` is a whole plan list behind a one-line
   * answer, and this page is usually read rather than edited. Answered once per exercise per visit
   * rather than on every open, because nothing *on this page* can change the answer — a plan built
   * in another tab is the one thing that can, and the same staleness is already assumed by
   * `inUseMessage` and by the delete it reports on.
   */
  function loadUsage(exerciseId: string) {
    if (usage[exerciseId]) return;
    setUsage((current) => ({ ...current, [exerciseId]: 'loading' }));
    plansUsingExercise(exerciseId)
      .then((names) => setUsage((current) => ({ ...current, [exerciseId]: names })))
      .catch(() => setUsage((current) => ({ ...current, [exerciseId]: 'unavailable' })));
  }

  /**
   * Saves the three fields the panel owns — its name, its group, and how it is performed.
   *
   * The sides flags go from the draft like every other field, and the note above the buttons is
   * what says they are not a rename: changing one re-lays-out every plan using this exercise. The
   * database is still the authority on the shapes it allows — `exercises_sides_shape` — and the
   * draft cannot express the pair it refuses.
   *
   * The name collision is left to the database rather than pre-checked against the list on screen,
   * for the same reason `onDelete` never pre-checks the foreign key: this list can be stale, and
   * the index that decides is `exercises_user_name_key` on `(user_id, lower(name))`. That is also
   * why the message is ours — Postgres's own names a constraint, not a fix.
   *
   * The blank check is here rather than left to the `required` attribute, which accepts a field
   * full of spaces: the column's own rule is `length(btrim(name)) > 0`, and that arrives as a
   * 23514 no one can read.
   */
  async function onSaveEdit(event: FormEvent, exercise: Exercise) {
    event.preventDefault();
    if (!draft) return;

    const trimmed = draft.name.trim();
    if (!trimmed) {
      setEditError('Give the exercise a name first.');
      return;
    }

    setSaving(true);
    setEditError(null);
    try {
      const updated = await updateExercise(exercise.id, {
        name: trimmed,
        muscle_group: draft.muscle_group,
        has_two_sides: draft.sides === 'two',
        alternates_sides: draft.sides === 'alternate',
      });
      // The row the server returned rather than a locally patched copy, so the list shows what is
      // actually stored. Re-sorted, because a new group moves it — that is where the next fetch
      // would put it, and a list that disagrees with the database until a reload is worse than a
      // row that jumps.
      setExercises((current) =>
        current.map((e) => (e.id === updated.id ? updated : e)).sort(byGroupThenName),
      );
      setDraft(null);
    } catch (err) {
      setEditError(
        isUniqueViolation(err)
          ? `You already have an exercise called "${trimmed}". Pick another name.`
          : errorMessage(err, 'Could not save the exercise'),
      );
    } finally {
      setSaving(false);
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
        <label className="inline-field" title="Performed once per side — left, then right">
          <input
            type="checkbox"
            checked={sides === 'two'}
            onChange={(e) => setSides(e.target.checked ? 'two' : 'none')}
          />
          <span>2 sides</span>
        </label>
        <label className="inline-field" title="Both sides alternately, inside one interval">
          <input
            type="checkbox"
            checked={sides === 'alternate'}
            onChange={(e) => setSides(e.target.checked ? 'alternate' : 'none')}
          />
          <span>Alternate</span>
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
          {filtered.map((exercise) => {
            const isEditing = draft?.id === exercise.id;
            // Computed per row rather than inside the form, so the one call that decides it is
            // outside the markup — same reason `exerciseSummary` is.
            const sidesNote = isEditing && draft ? sidesChangeNote(exercise, draft.sides) : null;
            return (
              <li
                key={exercise.id}
                className={isEditing ? 'card plan-row editing' : 'card plan-row'}
              >
                <div className="plan-main">
                  <span className="plan-name">{exercise.name}</span>
                  <span className="muted small">{exerciseSummary(exercise)}</span>
                </div>

                {/* The pair the Plans list shows, so the two pages read the same. Edit toggles
                    rather than opening a second panel: only one row is ever expanded, and its own
                    Cancel is the other way out. */}
                <div className="plan-actions">
                  <button
                    className="link-btn"
                    aria-expanded={isEditing}
                    onClick={() => openEditor(exercise)}
                  >
                    Edit
                  </button>
                  <button className="link-btn danger" onClick={() => void onDelete(exercise)}>
                    Delete
                  </button>
                </div>

                {/* Inside the row, so the thing being edited never leaves the screen — and
                    associated with it by containment rather than by a heading. */}
                {isEditing && draft && (
                  <form
                    className="exercise-edit"
                    onSubmit={(event) => void onSaveEdit(event, exercise)}
                    // Escape closes the panel, as it does in the builder's exercise picker.
                    onKeyDown={(event) => {
                      if (event.key !== 'Escape') return;
                      event.preventDefault();
                      closeEditor();
                    }}
                  >
                    <div className="exercise-edit-fields">
                      <label className="field">
                        <span>Name</span>
                        <input
                          autoFocus
                          required
                          value={draft.name}
                          onChange={(event) =>
                            setDraft({ ...draft, name: event.target.value })
                          }
                        />
                      </label>
                      <label className="field">
                        <span>Type</span>
                        <select
                          value={draft.muscle_group}
                          onChange={(event) =>
                            setDraft({ ...draft, muscle_group: event.target.value })
                          }
                        >
                          {groupOptions(exercise.muscle_group).map((group) => (
                            <option key={group} value={group}>
                              {group.replace('_', ' ')}
                            </option>
                          ))}
                        </select>
                      </label>
                      {/* The one field here that changes the workout's shape rather than its
                          label; the note below the row says what changing it does. A three-way
                          select rather than two checkboxes, for the reason `Sides` gives — this
                          panel can no more express "both" than the database can store it. */}
                      <label className="field">
                        <span>Sides</span>
                        <select
                          value={draft.sides}
                          onChange={(event) =>
                            setDraft({ ...draft, sides: event.target.value as Sides })
                          }
                        >
                          <option value="none">1 side</option>
                          <option value="two">2 sides (left, then right)</option>
                          <option value="alternate">Alternating (both sides per interval)</option>
                        </select>
                      </label>
                    </div>

                    {/* Said only while the change is staged, and it is the price of offering the
                        field at all: the flags re-lay-out every plan that uses this exercise, so
                        the consequence is named before Save rather than discovered afterwards. */}
                    {sidesNote && <p className="muted small">{sidesNote}</p>}

                    {/* Muted even when the check failed: the red in here is reserved for a save
                        that did not happen, which is the only thing needing an action. */}
                    <p className="muted small">{usageLine(usage[exercise.id])}</p>

                    {editError && <p className="error small">{editError}</p>}

                    <div className="exercise-edit-actions">
                      <button className="primary" type="submit" disabled={saving}>
                        {saving ? 'Saving…' : 'Save'}
                      </button>
                      {/* `type="button"` is required: inside a form, the default is submit. */}
                      <button className="secondary" type="button" onClick={closeEditor}>
                        Cancel
                      </button>
                    </div>
                  </form>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
