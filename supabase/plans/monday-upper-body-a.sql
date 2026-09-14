-- Loads "Monday — Upper Body A + HIIT" into the Oronzo account.
--
-- This is user data rather than a migration: it needs an account to attach the plan to.
-- Pasted into the Supabase SQL Editor, it finds the single user automatically.
--
-- Safe to re-run. It deletes and recreates only the plan with this exact name, so
-- re-running after an edit resets it to the prescription below.
--
-- How the workout maps onto the model. Both an exercise and a block can repeat:
--
--   "4 x 6-8 bench press, rest 90s"  -> ONE STEP with sets = 4 and rest_after = 90.
--                                       The set count belongs to the exercise, so the step
--                                       repeats on its own — no wrapper block needed.
--   "Rest: 90 sec"                   -> that step's rest_after, which fires after every
--                                       round including the last, so bench press carries
--                                       you into lat pulldown.
--   "6 x (20s hard, 40s easy)"       -> a BLOCK with rounds = 6 holding two timed steps.
--                                       Here the *group* repeats, which is what a block is
--                                       for. Steps and blocks therefore repeat at different
--                                       levels, and the words are kept distinct.
--
-- A step holds ONE rep target and ONE load, so where the programme gave ranges those are
-- pinned to the LOW end — the number you should always be able to hit — and the range
-- itself is kept in the step's notes.

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
  p_sets int, p_mode text, p_duration int, p_reps int,
  p_weight numeric, p_rest_after int, p_notes text
) returns void language plpgsql as $fn$
declare
  v_exercise uuid;
begin
  select id into v_exercise from public.exercises where slug = p_slug;
  if v_exercise is null then
    raise exception 'Unknown exercise slug "%". Run migrations/0002_seed_exercises.sql first.', p_slug;
  end if;

  insert into public.plan_steps (
    block_id, position, exercise_id, label, sets, mode,
    duration_seconds, reps, target_weight_kg, rest_after_seconds, notes
  ) values (
    p_block, p_position, v_exercise,
    nullif(p_label, ''), coalesce(p_sets, 1), p_mode,
    p_duration, p_reps, p_weight,
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

How to read this: an exercise's "sets" is its set count, and "rest between exercise
rounds" is the rest after each set — including the last, so it carries you into the next
exercise. A *block's* rounds instead repeats the whole group, which is how the HIIT
section works (6 rounds of 20 sec hard / 40 sec easy).

Aim for 1–2 reps in reserve on the working sets. Rep and weight ranges from the programme
are stored as their LOW end; the range itself is in each step's notes. Work up to the top
of the range on every set before adding load.

HIIT uses whatever cardio equipment you have. With none, replace the HIIT blocks with:
20 sec mountain climbers / 40 sec walking, ×6.

Note: the HIIT heading says 8 min, but 2 + (6 × 1) + 2 comes to 10 min. The blocks below
follow the intervals as written.
$notes$)
  returning id into v_plan;

  -- Warm-up — one pass through, no rest between the movements -----------------
  v_block := pg_temp.new_block(v_plan, 0, 'Warm-up', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'arm-circles',      null, 1, 'reps', null, 15, null, null, '15 reps in each direction');
  perform pg_temp.new_exercise_step(v_block, 1, 'scapular-push-up', null, 1, 'reps', null, 10, null, null, null);
  perform pg_temp.new_exercise_step(v_block, 2, 'inchworm',         null, 1, 'reps', null,  5, null, null, null);
  perform pg_temp.new_exercise_step(v_block, 3, 'push-up',          null, 1, 'reps', null, 10, null, null, null);
  perform pg_temp.new_exercise_step(v_block, 4, 'bench-press-dumbbell', 'Light DB Bench Press', 1, 'reps', null, 10, null, null, 'Light weight — this is a warm-up set');

  -- Main work — each exercise carries its own set count and rest --------------
  v_block := pg_temp.new_block(v_plan, 1, 'Main work', 1, null);

  perform pg_temp.new_exercise_step(v_block, 0, 'bench-press-dumbbell', 'Flat Dumbbell Bench Press',
    4, 'reps', null, 6, 20, 90, '20 kg per hand · 6–8 reps · aim for 1–2 reps in reserve');

  perform pg_temp.new_exercise_step(v_block, 1, 'lat-pulldown', 'Neutral-Grip Lat Pulldown',
    4, 'reps', null, 6, 50, 90, 'Start around 50 kg and build to 60 · 6–8 reps');

  perform pg_temp.new_exercise_step(v_block, 2, 'shoulder-press-dumbbell', 'Seated Dumbbell Shoulder Press',
    3, 'reps', null, 8, 12.5, 75, '12.5–15 kg per hand · 8–10 reps');

  perform pg_temp.new_exercise_step(v_block, 3, 'row-dumbbell', 'One-Arm Dumbbell Row',
    3, 'reps', null, 8, 20, 60, '20 kg · 8–10 reps, per side');

  perform pg_temp.new_exercise_step(v_block, 4, 'lateral-raise-dumbbell', 'Dumbbell Lateral Raise',
    3, 'reps', null, 12, 6, 45, '6–7.5 kg · 12–15 reps');

  perform pg_temp.new_exercise_step(v_block, 5, 'curl-hammer', 'Hammer Curl',
    2, 'reps', null, 10, 12.5, 45, '12.5–15 kg · 10–12 reps');

  -- HIIT — here a BLOCK repeats, because the group is what recurs ------------
  v_block := pg_temp.new_block(v_plan, 2, 'HIIT — warm-up', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Easy — 2 min',
    1, 'time', 120, null, null, null,
    'Treadmill or bike. No equipment? Swap the whole HIIT section for 20s mountain climbers / 40s walking, ×6.');

  v_block := pg_temp.new_block(v_plan, 3, 'HIIT — 6 rounds', 6, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Hard — 20 sec',
    1, 'time', 20, null, null, null, 'Around 8–9/10 effort — hard, but not an all-out sprint.');
  perform pg_temp.new_exercise_step(v_block, 1, 'treadmill-run', 'Easy — 40 sec',
    1, 'time', 40, null, null, null, null);

  v_block := pg_temp.new_block(v_plan, 4, 'HIIT — cool-down', 1, null);
  perform pg_temp.new_exercise_step(v_block, 0, 'treadmill-run', 'Easy — 2 min',
    1, 'time', 120, null, null, null, null);

  raise notice 'Loaded plan % with % blocks and % steps.', v_plan,
    (select count(*) from public.plan_blocks where plan_id = v_plan),
    (select count(*) from public.plan_steps s
       join public.plan_blocks b on b.id = s.block_id
      where b.plan_id = v_plan);
end;
$plan$;
