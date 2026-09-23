-- Loads "Thursday — Upper Body B + HIIT" into the Oronzo account.
--
-- This is user data rather than a migration: it needs an account to attach the plan to.
-- Pasted into the Supabase SQL Editor, it finds the single user automatically.
--
-- Run migrations/0002_seed_exercises.sql FIRST. Every movement below is in that file —
-- nothing here needs the five rows 0009 added, because this plan has no reverse lunge,
-- hip circles, bodyweight/dumbbell RDL or single-leg calf raise in it. `new_exercise_step`
-- raises on an unknown slug rather than skipping the step, so a missing migration is a loud
-- failure, not a quietly shorter workout.
--
-- Safe to re-run. It deletes and recreates only the plan with this exact name, so
-- re-running after an edit resets it to the prescription below. That delete cascades to the
-- plan's blocks and steps — but it does NOT touch workout history: `sessions.plan_id` is
-- `on delete set null`, and each session keeps its own copy of the plan name. Re-running
-- changes what you are about to do, never what you have already done.
--
-- How the workout maps onto the model. Both an exercise and a block can repeat:
--
--   "4 x 8-10 incline press, rest 90s" -> ONE STEP with sets = 4 and rest_after = 90. The set
--                                         count belongs to the exercise, so the step repeats
--                                         on its own — no wrapper block needed.
--   "Rest: 90 sec"                     -> that step's rest_after, which fires after every set
--                                         including the last, so the incline press carries you
--                                         into the one-arm row.
--   "6 x (20s hard, 40s easy)"         -> a BLOCK with rounds = 6 holding two timed steps.
--                                         Here the *group* repeats, which is what a block is
--                                         for. Steps and blocks therefore repeat at different
--                                         levels, and the words are kept distinct.
--
-- A step holds ONE rep target and ONE load, so where the programme gave ranges those are
-- pinned to the LOW end — the number you should always be able to hit. The range itself has
-- nowhere to live since `plan_steps.notes` was dropped in migration 0008, so it is kept as a
-- comment beside each step below. Work up to the top of the range on every set before
-- adding load. "Rest: 45-60 sec" is pinned the same way, to the 45.
--
-- --- The plan's own notes, kept here after `plans.notes` was dropped -----------------------
--
--   Target: hypertrophy / aesthetics.
--
--   Warm-up is the same five movements as Monday, and is stored identically to that plan's,
--   so the two warm-ups stay comparable.
--
--   All dumbbell loads are PER HAND. The one-arm row's "10 reps" is per side.
--
--   Lat pulldown is recorded as WIDE grip, which is the first of the two the programme
--   offers and the clearer contrast with Monday's neutral grip. To switch, change the one
--   `'Wide-Grip Lat Pulldown'` label below — the exercise row is the same either way.
--
--   Cable chest fly and cable triceps pushdown carry no load, because a cable stack reads
--   differently from one gym to the next. Pick a weight that makes the top of the rep range
--   genuinely hard.
--
--   Note: the HIIT heading says 8 min, but 2 + (6 × 1) + 2 comes to 10 min. The blocks below
--   follow the intervals as written — same discrepancy Monday's plan has, and the same
--   intervals.
--
--   HIIT uses whatever cardio equipment you have, as on Monday. With none, replace the HIIT
--   blocks with: 20 sec mountain climbers / 40 sec walking, ×6.
--
--   The incline curl's 45 sec rest is deliberate even though it is the last exercise: it
--   carries you into the HIIT warm-up, so the lift and the cardio are not back-to-back. The
--   HIIT cool-down has no rest, so the workout finishes at the end of it rather than on a
--   Break.
--
-- -------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- helpers. Created in pg_temp, so they exist only for this session and leave no
-- trace in the database.
-- ---------------------------------------------------------------------------

create or replace function pg_temp.new_block(
  p_plan uuid, p_position int, p_name text, p_rounds int, p_rest_between int
) returns uuid language sql as $fn$
  insert into public.plan_blocks (plan_id, position, name, rounds, rest_between_rounds_seconds)
  values (p_plan, p_position, p_name, p_rounds, p_rest_between)
  returning id;
$fn$;

create or replace function pg_temp.new_exercise_step(
  p_block uuid, p_position int, p_slug text, p_label text,
  p_sets int, p_mode text, p_duration int, p_reps int,
  p_weight numeric, p_rest_after int
) returns void language plpgsql as $fn$
declare
  v_exercise uuid;
begin
  select id into v_exercise from public.exercises where slug = p_slug;
  if v_exercise is null then
    raise exception 'Unknown exercise slug "%". Apply migrations/0002_seed_exercises.sql first.', p_slug;
  end if;

  insert into public.plan_steps (
    block_id, position, exercise_id, label, sets, mode,
    duration_seconds, reps, target_weight_kg, rest_after_seconds
  ) values (
    p_block, p_position, v_exercise,
    nullif(p_label, ''), coalesce(p_sets, 1), p_mode,
    p_duration, p_reps, p_weight,
    p_rest_after
  );
end;
$fn$;

-- ---------------------------------------------------------------------------
-- the plan
-- ---------------------------------------------------------------------------

do $plan$
declare
  v_user  uuid;
  v_plan  uuid;
  v_block uuid;
begin
  select id into v_user from auth.users order by created_at limit 1;
  if v_user is null then
    raise exception 'No account found. Create one under Authentication -> Users first.';
  end if;

  delete from public.plans where user_id = v_user and name = 'Thursday — Upper Body B + HIIT';

  insert into public.plans (user_id, name)
  values (v_user, 'Thursday — Upper Body B + HIIT')
  returning id into v_plan;

  -- Warm-up — one pass through, no rest between the movements -----------------
  -- The same five movements as Monday, recorded the same way.
  v_block := pg_temp.new_block(v_plan, 0, 'Warm-up', 1, null);
  -- 15 reps in each direction
  perform pg_temp.new_exercise_step(v_block, 0, 'arm-circles',      null, 1, 'reps', null, 15, null, null);
  perform pg_temp.new_exercise_step(v_block, 1, 'scapular-push-up', null, 1, 'reps', null, 10, null, null);
  perform pg_temp.new_exercise_step(v_block, 2, 'inchworm',         null, 1, 'reps', null,  5, null, null);
  perform pg_temp.new_exercise_step(v_block, 3, 'push-up',          null, 1, 'reps', null, 10, null, null);
  -- Light weight — this is a warm-up set
  perform pg_temp.new_exercise_step(v_block, 4, 'bench-press-dumbbell', 'Light DB Bench Press', 1, 'reps', null, 10, null, null);

  -- Workout — each exercise carries its own set count and rest ----------------
  v_block := pg_temp.new_block(v_plan, 1, 'Workout', 1, null);

  -- 17.5 kg per hand · 8-10 reps · bench around 30°, not excessively steep
  perform pg_temp.new_exercise_step(v_block, 0, 'incline-press-dumbbell', 'Incline Dumbbell Bench Press',
    4, 'reps', null, 8, 17.5, 90);

  -- 20 kg · 10 reps per side
  perform pg_temp.new_exercise_step(v_block, 1, 'row-dumbbell', 'One-Arm Dumbbell Row',
    4, 'reps', null, 10, 20, 60);

  -- 12-15 reps · no load recorded — see the note above
  perform pg_temp.new_exercise_step(v_block, 2, 'cable-fly', 'Cable Chest Fly',
    3, 'reps', null, 12, null, 45);

  -- 8-12 reps · a different grip from Monday's neutral one
  perform pg_temp.new_exercise_step(v_block, 3, 'lat-pulldown', 'Wide-Grip Lat Pulldown',
    3, 'reps', null, 8, null, 75);

  -- 6-7.5 kg per hand · 12-15 reps
  perform pg_temp.new_exercise_step(v_block, 4, 'lateral-raise-dumbbell', 'Dumbbell Lateral Raise',
    3, 'reps', null, 12, 6, 45);

  -- 10-15 reps · no load recorded — see the note above
  perform pg_temp.new_exercise_step(v_block, 5, 'triceps-pushdown', 'Cable Triceps Pushdown',
    2, 'reps', null, 10, null, 45);

  -- 10-12.5 kg per hand · 10-12 reps. The trailing 45 sec rest is deliberate — see the note above
  perform pg_temp.new_exercise_step(v_block, 6, 'curl-incline-dumbbell', 'Incline Dumbbell Curl',
    2, 'reps', null, 10, 10, 45);

  -- HIIT — here a BLOCK repeats, because the group is what recurs ------------
  -- The same protocol as Monday: 2 min easy, 6 x (20s hard / 40s easy), 2 min easy.
  v_block := pg_temp.new_block(v_plan, 2, 'HIIT — warm-up', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Easy — 2 min',
    1, 'time', 120, null, null, null);

  v_block := pg_temp.new_block(v_plan, 3, 'HIIT — 6 rounds', 6, null);
  -- Around 8–9/10 effort — hard, but not an all-out sprint.
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Hard — 20 sec',
    1, 'time', 20, null, null, null);
  perform pg_temp.new_exercise_step(v_block, 1, 'treadmill-run', 'Easy — 40 sec',
    1, 'time', 40, null, null, null);

  v_block := pg_temp.new_block(v_plan, 4, 'HIIT — cool-down', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Easy — 2 min',
    1, 'time', 120, null, null, null);

  raise notice 'Loaded plan % with % blocks and % steps.', v_plan,
    (select count(*) from public.plan_blocks where plan_id = v_plan),
    (select count(*) from public.plan_steps s
       join public.plan_blocks b on b.id = s.block_id
      where b.plan_id = v_plan);
end;
$plan$;
