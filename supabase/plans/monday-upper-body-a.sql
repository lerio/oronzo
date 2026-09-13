-- Loads "Monday — Upper Body A + HIIT" into the Oronzo account.
--
-- This is user data rather than a migration: it needs an account to attach the plan to.
-- Pasted into the Supabase SQL Editor, it finds the single user automatically.
--
-- Safe to re-run. It deletes and recreates only the plan with this exact name, so
-- re-running after an edit resets it to the prescription below.
--
-- How the workout maps onto the model:
--   "4 x 6-8"                  -> a block with rounds = 4, and reps 6 / reps_max 8
--   "Rest: 90 sec"             -> that block's rest_between_rounds_seconds
--   "50-60 kg"                 -> target_weight_kg 50 / target_weight_max_kg 60
--   "6 x (20s hard, 40s easy)" -> a block with rounds = 6 holding two timed steps
--   "1-2 reps in reserve", "/side", the Option B fallback -> step notes

-- ---------------------------------------------------------------------------
-- helpers. Created in pg_temp, so they exist only for this session and leave no
-- trace in the database.
-- ---------------------------------------------------------------------------

create or replace function pg_temp.ensure_exercise(
  p_slug text, p_name text, p_group text, p_equipment text,
  p_mode text, p_duration int, p_reps int
) returns void language sql as $fn$
  insert into public.exercises
    (slug, name, muscle_group, equipment, default_mode, default_duration_seconds, default_reps)
  values (p_slug, p_name, p_group, p_equipment, p_mode, p_duration, p_reps)
  on conflict (slug) do update set
    name = excluded.name,
    muscle_group = excluded.muscle_group,
    equipment = excluded.equipment,
    default_mode = excluded.default_mode,
    default_duration_seconds = excluded.default_duration_seconds,
    default_reps = excluded.default_reps;
$fn$;

create or replace function pg_temp.new_block(
  p_plan uuid, p_position int, p_name text, p_rounds int, p_rest_between int
) returns uuid language sql as $fn$
  insert into public.plan_blocks (plan_id, position, name, rounds, rest_between_rounds_seconds)
  values (p_plan, p_position, p_name, p_rounds, p_rest_between)
  returning id;
$fn$;

create or replace function pg_temp.new_exercise_step(
  p_block uuid, p_position int, p_slug text, p_label text,
  p_mode text, p_duration int, p_reps int, p_reps_max int,
  p_weight numeric, p_weight_max numeric, p_rest_after int, p_notes text
) returns void language plpgsql as $fn$
declare
  v_exercise uuid;
begin
  select id into v_exercise from public.exercises where slug = p_slug;
  if v_exercise is null then
    raise exception 'Unknown exercise slug "%". Run migrations/0002_seed_exercises.sql first.', p_slug;
  end if;

  insert into public.plan_steps (
    block_id, position, kind, exercise_id, label, mode,
    duration_seconds, reps, reps_max,
    target_weight_kg, target_weight_max_kg,
    rest_after_seconds, notes
  ) values (
    p_block, p_position, 'exercise', v_exercise,
    nullif(p_label, ''), p_mode,
    p_duration, p_reps, p_reps_max,
    p_weight, p_weight_max,
    p_rest_after, nullif(p_notes, '')
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

  -- The plan refers to these by slug; create them if this database predates them.
  perform pg_temp.ensure_exercise('arm-circles',      'Arm Circles',      'mobility',  'bodyweight', 'reps', null, 15);
  perform pg_temp.ensure_exercise('scapular-push-up', 'Scapular Push-Up', 'chest',     'bodyweight', 'reps', null, 10);
  perform pg_temp.ensure_exercise('inchworm',         'Inchworm',         'full_body', 'bodyweight', 'reps', null,  5);

  delete from public.plans where user_id = v_user and name = 'Monday — Upper Body A + HIIT';

  insert into public.plans (user_id, name, notes)
  values (v_user, 'Monday — Upper Body A + HIIT', $notes$
Target: strength + hypertrophy. Roughly 45–50 min.

How to read this: one block per exercise. A block's "rounds" is your set count, and its
"rest between rounds" is the rest between sets. The HIIT section is a 6-round block of
20 sec hard / 40 sec easy.

Aim for 1–2 reps in reserve on the working sets. The rep and weight ranges are the
progression: start at the low end, add reps within the range, then add load before you
add sets.

HIIT uses whatever cardio equipment you have. With none, replace the HIIT blocks with:
20 sec mountain climbers / 40 sec walking, ×6.

Note: the HIIT heading says 8 min, but 2 + (6 × 1) + 2 comes to 10 min. The blocks below
follow the intervals as written.
$notes$)
  returning id into v_plan;

  -- Warm-up -----------------------------------------------------------------
  v_block := pg_temp.new_block(v_plan, 0, 'Warm-up', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'arm-circles',      null, 'reps', null, 15, null, null, null, null, '15 reps in each direction');
  perform pg_temp.new_exercise_step(v_block, 1, 'scapular-push-up', null, 'reps', null, 10, null, null, null, null, null);
  perform pg_temp.new_exercise_step(v_block, 2, 'inchworm',         null, 'reps', null,  5, null, null, null, null, null);
  perform pg_temp.new_exercise_step(v_block, 3, 'push-up',          null, 'reps', null, 10, null, null, null, null, null);
  perform pg_temp.new_exercise_step(v_block, 4, 'bench-press-dumbbell', 'Light DB Bench Press', 'reps', null, 10, null, null, null, null, 'Light weight — this is a warm-up set');

  -- Main work: one block per exercise, rounds = sets -------------------------
  v_block := pg_temp.new_block(v_plan, 1, 'Flat Dumbbell Bench Press', 4, 90);
  perform pg_temp.new_exercise_step(v_block, 0, 'bench-press-dumbbell', 'Flat Dumbbell Bench Press',
    'reps', null, 6, 8, 20, null, null, '20 kg per hand. Aim for 1–2 reps in reserve.');

  v_block := pg_temp.new_block(v_plan, 2, 'Neutral-Grip Lat Pulldown', 4, 90);
  perform pg_temp.new_exercise_step(v_block, 0, 'lat-pulldown', 'Neutral-Grip Lat Pulldown',
    'reps', null, 6, 8, 50, 60, null, 'Start around 50–60 kg, then adjust.');

  v_block := pg_temp.new_block(v_plan, 3, 'Seated Dumbbell Shoulder Press', 3, 75);
  perform pg_temp.new_exercise_step(v_block, 0, 'shoulder-press-dumbbell', 'Seated Dumbbell Shoulder Press',
    'reps', null, 8, 10, 12.5, 15, null, null);

  v_block := pg_temp.new_block(v_plan, 4, 'One-Arm Dumbbell Row', 3, 60);
  perform pg_temp.new_exercise_step(v_block, 0, 'row-dumbbell', 'One-Arm Dumbbell Row',
    'reps', null, 8, 10, 20, null, null, 'Reps are per side.');

  v_block := pg_temp.new_block(v_plan, 5, 'Dumbbell Lateral Raise', 3, 45);
  perform pg_temp.new_exercise_step(v_block, 0, 'lateral-raise-dumbbell', 'Dumbbell Lateral Raise',
    'reps', null, 12, 15, 6, 7.5, null, null);

  v_block := pg_temp.new_block(v_plan, 6, 'Hammer Curl', 2, 45);
  perform pg_temp.new_exercise_step(v_block, 0, 'curl-hammer', 'Hammer Curl',
    'reps', null, 10, 12, 12.5, 15, null, null);

  -- HIIT --------------------------------------------------------------------
  v_block := pg_temp.new_block(v_plan, 7, 'HIIT — warm-up', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Easy — 2 min',
    'time', 120, null, null, null, null, null,
    'Treadmill or bike. No equipment? Swap the whole HIIT section for 20s mountain climbers / 40s walking, ×6.');

  v_block := pg_temp.new_block(v_plan, 8, 'HIIT — 6 rounds', 6, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Hard — 20 sec',
    'time', 20, null, null, null, null, null, 'Around 8–9/10 effort — hard, but not an all-out sprint.');
  perform pg_temp.new_exercise_step(v_block, 1, 'treadmill-run', 'Easy — 40 sec',
    'time', 40, null, null, null, null, null, null);

  v_block := pg_temp.new_block(v_plan, 9, 'HIIT — cool-down', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Easy — 2 min',
    'time', 120, null, null, null, null, null, null);

  raise notice 'Loaded plan % with % blocks.', v_plan,
    (select count(*) from public.plan_blocks where plan_id = v_plan);
end;
$plan$;
