-- Rep ranges and weight ranges.
--
-- Hypertrophy programming is written as ranges — "4 x 6-8", "50-60 kg" — so a single
-- integer target misrepresents the prescription and loses the intended progression room.
--
-- The design keeps `reps` / `target_weight_kg` as the BASE of the range (the number you
-- start at) and adds an optional ceiling. Both are needed: a range with no base is
-- meaningless, and enforcement of that lives in the constraint below rather than in the
-- client.
--
-- Deliberately NOT modelled: "per side" and "1-2 reps in reserve". Those are annotations
-- about how to perform a set, not values the execution engine needs — a rep step simply
-- waits for a tap either way — so they live in `notes`.

alter table public.plan_steps
  add column if not exists reps_max integer check (reps_max > 0),
  add column if not exists target_weight_max_kg numeric(6, 2) check (target_weight_max_kg >= 0);

-- A ceiling only makes sense alongside a floor, and must not be below it.
alter table public.plan_steps
  drop constraint if exists plan_steps_range_shape;
alter table public.plan_steps
  add constraint plan_steps_range_shape check (
    (reps_max is null or (reps is not null and reps_max >= reps))
    and (
      target_weight_max_kg is null
      or (target_weight_kg is not null and target_weight_max_kg >= target_weight_kg)
    )
  );

-- History snapshots the planned values, so it needs the ceilings too.
alter table public.session_steps
  add column if not exists planned_reps_max integer,
  add column if not exists planned_weight_max_kg numeric(6, 2);

-- ---------------------------------------------------------------------------
-- save_plan, extended to carry the new fields.
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
        block_id, position, kind, exercise_id, label, mode,
        duration_seconds, reps, reps_max,
        target_weight_kg, target_weight_max_kg,
        rest_after_seconds, notes
      ) values (
        v_block_id,
        v_step_pos,
        coalesce(nullif(v_step->>'kind', ''), 'exercise'),
        nullif(v_step->>'exercise_id', '')::uuid,
        nullif(v_step->>'label', ''),
        coalesce(nullif(v_step->>'mode', ''), 'reps'),
        nullif(v_step->>'duration_seconds', '')::int,
        nullif(v_step->>'reps', '')::int,
        nullif(v_step->>'reps_max', '')::int,
        nullif(v_step->>'target_weight_kg', '')::numeric,
        nullif(v_step->>'target_weight_max_kg', '')::numeric,
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
