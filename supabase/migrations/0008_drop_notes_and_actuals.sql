-- Remove two capabilities the app had stopped honouring, rather than add one.
--
--   * `notes`, on `plans` and on `plan_steps`. Plan notes were dropped from the builder
--     already; step notes were still editable in the builder, but iOS decoded them and threw
--     them away, so anything typed there ("per side", "1–2 reps in reserve") never reached
--     the screen you would want it on. Half-supporting a field is worse than not having it.
--
--   * `session_steps.actual_reps` and `actual_weight_kg`. The engine could record them, but
--     nothing ever called `record(reps:weightKg:)` — the runner has no UI for entering what
--     you actually lifted — so every logged session stored nulls where the MVP promised
--     "per-step actuals".
--
-- `actual_duration_seconds` and `status` STAY. Both are genuinely populated by the engine,
-- and between them they are what makes the history worth keeping.
--
-- NOTE: `exercises.notes` is deliberately untouched. That is the exercise library's own
-- seeded coaching text, a different field with a different purpose.

-- ---------------------------------------------------------------------------
-- Say what this costs, before it costs it. These columns hold the user's own writing, and a
-- migration that discards text without reporting it is one nobody can audit afterwards.
-- ---------------------------------------------------------------------------

do $report$
declare
  v_plans integer;
  v_steps integer;
begin
  select count(*) into v_plans from public.plans where coalesce(notes, '') <> '';
  select count(*) into v_steps from public.plan_steps where coalesce(notes, '') <> '';
  raise notice 'Dropping notes: % plan(s) and % step(s) currently have notes; that text will be lost.', v_plans, v_steps;
end;
$report$;

-- ---------------------------------------------------------------------------
-- save_plan without `notes`, redefined BEFORE the columns are dropped — its body writes to
-- both of them, so dropping first would leave the function broken until it was replaced.
-- ---------------------------------------------------------------------------

create or replace function public.save_plan(payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_plan_id   uuid;
  v_block     jsonb;
  v_step      jsonb;
  v_block_id  uuid;
  v_block_pos integer := 0;
  v_step_pos  integer;
begin
  if v_user is null then
    raise exception 'save_plan: not authenticated' using errcode = '28000';
  end if;

  v_plan_id := coalesce(nullif(payload->>'id', '')::uuid, gen_random_uuid());

  insert into public.plans (id, user_id, name)
  values (v_plan_id, v_user, payload->>'name')
  on conflict (id) do update
    set name = excluded.name
    where public.plans.user_id = v_user;

  if not exists (select 1 from public.plans where id = v_plan_id and user_id = v_user) then
    raise exception 'save_plan: plan % not found for this user', v_plan_id using errcode = '42501';
  end if;

  delete from public.plan_blocks where plan_id = v_plan_id;

  for v_block in select * from jsonb_array_elements(coalesce(payload->'blocks', '[]'::jsonb))
  loop
    insert into public.plan_blocks (plan_id, position, name, rounds, rest_between_rounds_seconds)
    values (
      v_plan_id,
      v_block_pos,
      nullif(v_block->>'name', ''),
      coalesce((v_block->>'rounds')::int, 1),
      nullif(v_block->>'rest_between_rounds_seconds', '')::int
    )
    returning id into v_block_id;

    v_step_pos := 0;
    for v_step in select * from jsonb_array_elements(coalesce(v_block->'steps', '[]'::jsonb))
    loop
      insert into public.plan_steps (
        block_id, position, exercise_id, label, sets, mode,
        duration_seconds, reps, target_weight_kg, rest_after_seconds
      ) values (
        v_block_id,
        v_step_pos,
        nullif(v_step->>'exercise_id', '')::uuid,
        nullif(v_step->>'label', ''),
        coalesce(nullif(v_step->>'sets', '')::int, 1),
        coalesce(nullif(v_step->>'mode', ''), 'reps'),
        nullif(v_step->>'duration_seconds', '')::int,
        nullif(v_step->>'reps', '')::int,
        nullif(v_step->>'target_weight_kg', '')::numeric,
        nullif(v_step->>'rest_after_seconds', '')::int
      );
      v_step_pos := v_step_pos + 1;
    end loop;

    v_block_pos := v_block_pos + 1;
  end loop;

  return v_plan_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Now the columns can go.
-- ---------------------------------------------------------------------------

alter table public.plans       drop column if exists notes;
alter table public.plan_steps  drop column if exists notes;

alter table public.session_steps
  drop column if exists actual_reps,
  drop column if exists actual_weight_kg;

grant execute on function public.save_plan(jsonb) to authenticated;
