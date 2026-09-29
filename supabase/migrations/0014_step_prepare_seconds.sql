-- `plan_steps.prepare_seconds` — a "Get in position" interval in front of a timed step.
--
-- A timed interval begins the instant the previous one ends, so the first seconds of a hold are
-- spent getting into the hold instead of doing it. The fix is a short interval in front of the
-- work, and **the plan decides which steps want one**: a timed step is not always work, since the
-- seeded HIIT blocks prescribe their recoveries as timed steps too ("Easy — 40 sec", "Recover"),
-- and nothing in the model tells a recovery apart from a hold. A rule in the flattener would have
-- had to guess; a column lets the author answer.
--
-- It is a duration rather than a boolean, so that a per-step value would need no second migration.
-- Five seconds is the only value the builder offers today, and it is the builder's constant, not
-- the database's — this column accepts any positive number of seconds.
--
-- Nullable, and null is every existing row: nothing an app already runs changes what it emits.
-- Null means none, so `> 0` rather than `>= 0` — there is exactly one way to say "no prepare".
--
-- `save_plan` is redefined for the eighth time — it re-encodes the plan tree, so a column it does
-- not write is a column the builder cannot save.
--
-- NOTE: append-only, and `0013`'s definition is superseded by this one.
--
-- ORDERING, and it is the opposite of the usual worry: this column is additive, so an older
-- client keeps working after it is applied — but a save from an **older deployed web bundle**
-- would wipe it, because `save_plan` replaces the whole tree and that bundle does not send the
-- key. Apply this and deploy the builder in the same sitting, before any box is ticked.

alter table public.plan_steps
  add column prepare_seconds integer check (prepare_seconds > 0);

-- ---------------------------------------------------------------------------
-- save_plan, now with `prepare_seconds` in both lists.
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
        duration_seconds, reps, target_weight_kg, rest_after_seconds, intensity,
        prepare_seconds
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
        nullif(v_step->>'intensity', ''),
        nullif(v_step->>'prepare_seconds', '')::int
      );
      v_step_pos := v_step_pos + 1;
    end loop;

    v_block_pos := v_block_pos + 1;
  end loop;

  return v_plan_id;
end;
$$;

-- A redefined function needs its grant re-stated — `create or replace` does not preserve it in
-- every case, and every migration that redefines `save_plan` re-issues this line. (`0013` did not;
-- that is missing rather than deliberate, and re-issuing it here is harmless either way.)
grant execute on function public.save_plan(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- What the column holds, as a result rather than a notice.
-- ---------------------------------------------------------------------------

select
  count(*)                                            as steps,
  count(*) filter (where prepare_seconds is not null) as with_a_prepare,
  count(*) filter (where mode = 'time')               as timed;
