-- Loads "Tuesday — Lower Body A" into the Oronzo account.
--
-- This is user data rather than a migration: it needs an account to attach the plan to.
-- Pasted into the Supabase SQL Editor, it finds the single user automatically.
--
-- Run migrations/0009_seed_more_exercises.sql FIRST. Five of the movements below — reverse
-- lunge, hip circles, bodyweight RDL, dumbbell RDL, single-leg calf raise — exist in the
-- library only from that file. `new_exercise_step` raises on an unknown slug rather than
-- skipping the step, so a missing migration is a loud failure, not a quietly shorter workout.
--
-- Safe to re-run. It deletes and recreates only the plan with this exact name, so
-- re-running after an edit resets it to the prescription below.
--
-- How the workout maps onto the model. Both an exercise and a block can repeat:
--
--   "4 x 8-10 goblet squat, rest 90s" -> ONE STEP with sets = 4 and rest_after = 90. The set
--                                        count belongs to the exercise, so the step repeats
--                                        on its own — no wrapper block needed.
--   "Rest: 90 sec"                    -> that step's rest_after, which fires after every set
--                                        including the last, so the goblet squat carries you
--                                        into the dumbbell RDL.
--   "Warm-up: five movements, once"   -> a BLOCK with rounds = 1 and no rest between the
--                                        movements; the list is the group.
--
-- A step holds ONE rep target and ONE load, so where the programme gave ranges those are
-- pinned to the LOW end — the number you should always be able to hit. The range itself has
-- nowhere to live since `plan_steps.notes` was dropped in migration 0008, so it is kept as a
-- comment beside each step below. Work up to the top of the range on every set before
-- adding load.
--
-- --- The plan's own notes, kept here after `plans.notes` was dropped -----------------------
--
--   Target: strength + leg development. Warm-up is about 5 min.
--
--   Goblet squat: when 20 kg becomes too easy, move to a double-dumbbell front squat or
--   eventually a barbell squat.
--
--   Leg extension: "challenging weight" — no load is recorded, because a machine stack is
--   not the same from one gym to the next. Pick a weight that makes 10-15 reps genuinely
--   hard.
--
--   Reverse lunge, Bulgarian split squat and single-leg calf raise are counted PER LEG: the
--   rep target is per leg, not the total. Dumbbell loads are PER HAND.
--
--   The ab wheel step carries a 60 sec rest like every other step, and `rest_after` fires
--   after the final set too — so the workout ends on a Break. Delete the `60` from the last
--   step below if you would rather it just finish.
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
    raise exception 'Unknown exercise slug "%". Apply migrations/0002 and 0009 first.', p_slug;
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

  delete from public.plans where user_id = v_user and name = 'Tuesday — Lower Body A';

  insert into public.plans (user_id, name)
  values (v_user, 'Tuesday — Lower Body A')
  returning id into v_plan;

  -- Warm-up — one pass through, no rest between the movements -----------------
  -- Roughly 5 min. Every movement is performed once; the block's rounds = 1.
  v_block := pg_temp.new_block(v_plan, 0, 'Warm-up', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'squat-bodyweight', null, 1, 'reps', null, 15, null, null);
  -- 8 per leg
  perform pg_temp.new_exercise_step(v_block, 1, 'lunge-reverse',    null, 1, 'reps', null,  8, null, null);
  perform pg_temp.new_exercise_step(v_block, 2, 'glute-bridge',     null, 1, 'reps', null, 15, null, null);
  -- 10 in each direction
  perform pg_temp.new_exercise_step(v_block, 3, 'hip-circles',      null, 1, 'reps', null, 10, null, null);
  perform pg_temp.new_exercise_step(v_block, 4, 'rdl-bodyweight',   null, 1, 'reps', null, 10, null, null);

  -- Workout — each exercise carries its own set count and rest ----------------
  v_block := pg_temp.new_block(v_plan, 1, 'Workout', 1, null);

  -- 20 kg · 8-10 reps
  perform pg_temp.new_exercise_step(v_block, 0, 'goblet-squat', null,
    4, 'reps', null, 8, 20, 90);

  -- 20 kg per hand · 8-10 reps
  perform pg_temp.new_exercise_step(v_block, 1, 'rdl-dumbbell', null,
    4, 'reps', null, 8, 20, 90);

  -- 15-17.5 kg per hand · 8-10 reps per leg
  perform pg_temp.new_exercise_step(v_block, 2, 'split-squat-bulgarian', null,
    3, 'reps', null, 8, 15, 75);

  -- Challenging weight · 10-15 reps. No load recorded — see the note above.
  perform pg_temp.new_exercise_step(v_block, 3, 'leg-extension', null,
    3, 'reps', null, 10, null, 60);

  -- 20 kg · 12-15 reps per leg
  perform pg_temp.new_exercise_step(v_block, 4, 'calf-raise-single-leg', null,
    3, 'reps', null, 12, 20, 45);

  -- 8-12 reps. The trailing 60 sec rest is deliberate — see the note above.
  perform pg_temp.new_exercise_step(v_block, 5, 'ab-wheel-rollout', null,
    3, 'reps', null, 8, null, 60);

  raise notice 'Loaded plan % with % blocks and % steps.', v_plan,
    (select count(*) from public.plan_blocks where plan_id = v_plan),
    (select count(*) from public.plan_steps s
       join public.plan_blocks b on b.id = s.block_id
      where b.plan_id = v_plan);
end;
$plan$;
