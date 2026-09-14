-- Removes rep and weight ranges again. 0003 added them; they turned out to be more
-- machinery than the plan builder wants, so a step carries one rep target and one load.
--
-- Any range that was already entered keeps its BASE value (`reps`, `target_weight_kg`) and
-- loses only the ceiling, so no prescription becomes empty. The nuance that a range
-- carried — "work up to 8", "start at 50 and add" — belongs in the step's notes.

alter table public.plan_steps
  drop constraint if exists plan_steps_range_shape;

alter table public.plan_steps
  drop column if exists reps_max,
  drop column if exists target_weight_max_kg;

alter table public.session_steps
  drop column if exists planned_reps_max,
  drop column if exists planned_weight_max_kg;

-- Restore save_plan to its pre-range form.
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
        duration_seconds, reps, target_weight_kg, rest_after_seconds, notes
      ) values (
        v_block_id,
        v_step_pos,
        coalesce(nullif(v_step->>'kind', ''), 'exercise'),
        nullif(v_step->>'exercise_id', '')::uuid,
        nullif(v_step->>'label', ''),
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
