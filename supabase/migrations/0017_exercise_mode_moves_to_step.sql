-- The reps/time choice belongs to the step, not the exercise.
--
-- `default_mode` and its two per-mode defaults were only ever a prefill for a new plan step;
-- `plan_steps.mode`, `duration_seconds` and `reps` already carry everything the flattener reads.
-- An exercise is now usable either way, and the mode is chosen in the plan builder, so these
-- three columns have nothing left to say.
--
-- Dropping `default_mode` drops `exercises_mode_shape` with it — that constraint exists only to
-- require a duration for a time-mode row.
--
-- **Ordering.** The new web bundle neither reads nor writes these columns, so it works before or
-- after this file. The *old* bundle names them on insert, which is a `400` once they are gone, so
-- deploy the web app first and apply this after. Nothing in the iOS app reads the columns.

alter table public.exercises
  drop column default_mode,
  drop column default_duration_seconds,
  drop column default_reps;

-- ---------------------------------------------------------------------------
-- What is left, as a result rather than a notice.
-- ---------------------------------------------------------------------------

select
  count(*)                            as exercises,
  count(*) filter (where has_two_sides)    as two_sided,
  count(*) filter (where alternates_sides) as alternating;
