-- Oronzo — five exercises the seed library was missing.
--
-- Found while loading "Tuesday — Lower Body A". That plan calls for a reverse lunge, hip
-- circles, a bodyweight and a dumbbell Romanian deadlift, and a single-leg calf raise — and
-- `0002_seed_exercises.sql` had none of them.
--
-- Only the dumbbell RDL had a near neighbour there (`romanian-deadlift`, which is the
-- barbell one). Reusing it would have recorded a dumbbell lift under a barbell exercise in
-- the session history, and the library already keeps separate rows per equipment variant
-- (`bench-press-barbell` / `bench-press-dumbbell`), so these follow that convention rather
-- than aliasing onto a neighbouring row. `hip-circles` had nothing defensible at all.
--
-- Seeded rows are owned by nobody (user_id IS NULL) and identified by `slug`. This follows
-- `0002` exactly — idempotent, `on conflict (slug) do update`, and structurally unable to
-- touch a custom exercise the user created, which has an owner and no slug.
--
-- NOTE: migrations are append-only, so this is a new file rather than an edit to `0002`.

insert into public.exercises
  (slug, name, muscle_group, equipment, default_mode, default_duration_seconds, default_reps)
values
  -- quads
  ('lunge-reverse',          'Reverse Lunge',              'quads',      'bodyweight', 'reps', null,  8),
  -- hamstrings — two rows, because bodyweight and dumbbell are different loads
  ('rdl-bodyweight',         'Bodyweight RDL',             'hamstrings', 'bodyweight', 'reps', null, 10),
  ('rdl-dumbbell',           'Dumbbell Romanian Deadlift', 'hamstrings', 'dumbbell',   'reps', null,  8),
  -- calves
  ('calf-raise-single-leg',  'Single-Leg Calf Raise',      'calves',     'bodyweight', 'reps', null, 12),
  -- mobility
  ('hip-circles',            'Hip Circles',                'mobility',   'bodyweight', 'reps', null, 10)
on conflict (slug) do update set
  name                     = excluded.name,
  muscle_group             = excluded.muscle_group,
  equipment                = excluded.equipment,
  default_mode             = excluded.default_mode,
  default_duration_seconds = excluded.default_duration_seconds,
  default_reps             = excluded.default_reps;
