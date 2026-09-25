-- `plan_steps.intensity` — how hard a timed step is meant to be: low, medium or hard.
--
-- A timed interval is prescribed as a duration *and* an effort, and until now the effort only had
-- somewhere to live as free text. The seeded plans write it into the step's `label` ("Hard — 20
-- sec", "Easy — 2 min") and `PlanFlattener` prefers a label over the exercise name, so it reached
-- the screen — but as a name, not as a value anything could reason about, and no input in the
-- builder can set a label at all (`docs/known-issues.md` §1). This is the structured version.
--
-- It sits on the *step*, not the exercise: a HIIT block is hard and easy steps side by side, and
-- the same exercise is done at both. Nullable, because a strength hold is just a hold — and only
-- offered for `mode = 'time'` in the builder, which is where the ask came from.
--
-- The three words are policed here rather than in the client, exactly as `mode` is: a check
-- constraint, so a fourth word cannot exist and every surface can switch on the enum exhaustively.
--
-- `save_plan` is redefined for the seventh time — it re-encodes the plan tree, so a column it
-- does not write is a column the builder cannot save.
--
-- NOTE: append-only, and `0008`'s definition is superseded by this one. Nothing else reads the
-- column: `Interval` carries it as an *optional* field, so an older snapshot still decodes and a
-- nil one is omitted from the JSON entirely (`docs/decisions.md`).

alter table public.plan_steps
  add column intensity text check (intensity in ('low', 'medium', 'hard'));

-- ---------------------------------------------------------------------------
-- save_plan, now with `intensity` in both lists.
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
        duration_seconds, reps, target_weight_kg, rest_after_seconds, intensity
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
        nullif(v_step->>'intensity', '')
      );
      v_step_pos := v_step_pos + 1;
    end loop;

    v_block_pos := v_block_pos + 1;
  end loop;

  return v_plan_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- What the column holds, as a result rather than a notice.
-- ---------------------------------------------------------------------------

select
  count(*)                                        as steps,
  count(*) filter (where intensity is not null)   as with_an_intensity,
  count(*) filter (where mode = 'time')           as timed;
