-- Exercises get their own set count.
--
-- Until now only a *block* could repeat, so "4 x 6-8 bench press" had to be modelled as a
-- block wrapping a single step. That worked but read backwards: the set count belongs to
-- the exercise, not to a group containing one thing. Now both can repeat, and the two
-- words mean different things:
--
--   plan_steps.sets    repeat one exercise -> "4 x 6-8 bench press"      (sets)
--   plan_blocks.rounds repeat the whole group -> "6 x (20s hard, 40s easy)" (rounds)
--
-- `rest_after_seconds` keeps its behaviour: it fires after EACH set of the step, including
-- the final one, so an exercise's rest carries you into the next exercise. Its label in the
-- builder is "rest between exercise rounds", which describes its main job; the trailing
-- rest is deliberate (agreed 2026-09-14).

alter table public.plan_steps
  add column if not exists sets integer not null default 1;

alter table public.plan_steps
  drop constraint if exists plan_steps_sets_positive;
alter table public.plan_steps
  add constraint plan_steps_sets_positive check (sets >= 1);

-- The session record has always wanted to say "which set of the exercise was this"; now it
-- can, and the name says so. block_round is the other dimension: which pass through the
-- block.
do $rename$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'session_steps' and column_name = 'round_index'
  ) then
    alter table public.session_steps rename column round_index to set_index;
  end if;
end;
$rename$;

alter table public.session_steps
  add column if not exists block_round integer;

comment on column public.session_steps.set_index is
  'Which set of the exercise this was (1-based).';
comment on column public.session_steps.block_round is
  'Which round of the enclosing block this was (1-based).';

-- ---------------------------------------------------------------------------
-- save_plan, carrying the set count.
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
        block_id, position, kind, exercise_id, label, sets, mode,
        duration_seconds, reps, target_weight_kg, rest_after_seconds, notes
      ) values (
        v_block_id,
        v_step_pos,
        coalesce(nullif(v_step->>'kind', ''), 'exercise'),
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
