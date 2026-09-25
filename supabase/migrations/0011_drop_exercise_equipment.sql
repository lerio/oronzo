-- `equipment` goes. It was a seeded-library idea — that library kept a separate row per
-- equipment variant (`bench-press-barbell` / `bench-press-dumbbell`), and `0010` removed every
-- one of those rows. What would be left is a tag nothing filters on and the builder no longer
-- asks for, so every new exercise would take its 'bodyweight' default and go on saying so
-- forever.
--
-- Nothing outside the web app reads it. iOS fetches the exercise list with `.select("id,name")`,
-- so dropping a column cannot break the phone's hand-written PostgREST select — the failure
-- mode that has cost this project real time before.
--
-- NOTE: append-only. `0002` and `0009` still write `equipment` and stay exactly as they are:
-- they run before this file, against a schema that still has the column.

alter table public.exercises drop column equipment;

-- ---------------------------------------------------------------------------
-- That the rows are all still there, as a result rather than a notice.
-- ---------------------------------------------------------------------------

select
  count(*)                        as exercises,
  count(default_duration_seconds) as timed,
  count(default_reps)             as rep_based;
