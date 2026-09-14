-- A step is an exercise. The rest/exercise distinction goes away.
--
-- Rest is now expressed where it actually belongs, rather than as a step that pretends to
-- be one:
--
--   step.rest_after_seconds      rest after each set of that exercise
--   block.rest_between_rounds_seconds  rest between rounds of a group
--
-- A standalone rest step had nothing left to do, and it could not be edited once the
-- builder stopped offering the choice, so it is gone rather than merely hidden.
--
-- NOTE: the execution stream still distinguishes exercises from rests — a synthetic rest
-- interval is emitted between sets. `session_steps.kind` and `Interval.kind` therefore
-- stay; only the *plan* stops pretending a rest is a kind of exercise.

-- ---------------------------------------------------------------------------
-- Any existing rest steps have to go: with `kind` removed they would be steps with no
-- exercise, which the last constraint below forbids. They carry nothing but a duration.
-- Reported rather than silent.
-- ---------------------------------------------------------------------------

do $cleanup$
declare
  v_removed integer;
begin
  delete from public.plan_steps where kind = 'rest';
  get diagnostics v_removed = row_count;
  if v_removed > 0 then
    raise notice 'Removed % standalone rest step(s). Use a step''s "rest between exercise rounds", or a block''s "rest between rounds", instead.', v_removed;
  end if;
end;
$cleanup$;

-- Constraints that referenced `kind` must go before the column can.
alter table public.plan_steps drop constraint if exists plan_steps_shape;
alter table public.plan_steps drop constraint if exists plan_steps_exercise_required;
alter table public.plan_steps drop constraint if exists plan_steps_mode_shape;

alter table public.plan_steps drop column if exists kind;

-- Now that a step is always an exercise, these hold unconditionally.
alter table public.plan_steps alter column exercise_id set not null;

alter table public.plan_steps
  add constraint plan_steps_mode_shape check (
    (mode = 'time' and duration_seconds is not null)
    or (mode = 'reps' and reps is not null)
  );

-- ---------------------------------------------------------------------------
-- save_plan without `kind`.
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

  insert into public.plans (id, user_id, name, notes)
  values (v_plan_id, v_user, payload->>'name', payload->>'notes')
  on conflict (id) do update
    set name = excluded.name,
        notes = excluded.notes
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
        duration_seconds, reps, target_weight_kg, rest_after_seconds, notes
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
        nullif(v_step->>'rest_after_seconds', '')::int,
        nullif(v_step->>'notes', '')
      );
      v_step_pos := v_step_pos + 1;
    end loop;

    v_block_pos := v_block_pos + 1;
  end loop;

  return v_plan_id;
end;
$$;

grant execute on function public.save_plan(jsonb) to authenticated;
