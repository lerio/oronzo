-- `plans.position` — the order the user arranges their plans in.
--
-- The list was ordered by `updated_at desc`, which is a side effect of editing rather than a
-- choice: opening a plan and pressing Save moved it to the top, and there was no way to say "this
-- one first". A position column makes the order the user's own, and both clients read it — the
-- web builder and the iPhone — so the two agree.
--
-- The column is `not null` with **no default**, matching `plan_blocks.position` and
-- `plan_steps.position`. Every writer says where a plan goes: `save_plan` for anything authored in
-- the builder, and the three hand-run scripts in `supabase/plans/`, which were changed with this
-- migration to append rather than to take a top spot — they *restore* a plan that was already in
-- the list, so they must not disturb an order the user has arranged. Those scripts must therefore
-- be run **after** this file; before it, they name a column that does not exist. A default would
-- have been a loaded gun: a writer that forgot `position` would quietly land on 0 and collide with
-- whoever holds 0, and — because the constraint below is deferred — the failure would arrive at
-- COMMIT, after the function had already returned.
--
-- `unique (user_id, position)` is DEFERRABLE INITIALLY DEFERRED, which its two siblings are not,
-- and that is not decoration. `reorder_plans` and `save_plan` both move every row of a user's list
-- in one statement, and PostgreSQL checks a NON-deferrable unique constraint **per row**, so
-- renumbering 0,1,2 to 1,2,0 collides on an intermediate state that is never committed. Deferring
-- moves the check to COMMIT — PostgREST runs every request, RPCs included, in one transaction, so
-- that commit is the end of the request. Two consequences worth knowing: a violation surfaces at
-- COMMIT rather than from the statement that caused it, so **neither function can catch it** and
-- the caller sees a `duplicate key value violates unique constraint "plans_user_position_key"`
-- raised after the RPC has already returned; and a deferrable constraint can never serve as an
-- `ON CONFLICT` arbiter. Only the arbiter is restricted, though — `save_plan` arbitrates on the
-- primary key, which is not deferrable, so it is unaffected. (Verified against the PostgreSQL
-- docs for `INSERT`, which state that in all cases only NOT DEFERRABLE constraints and unique
-- indexes are supported *as arbiters*, and inference for `on conflict (id)` can only pick
-- `plans_pkey`.) The one path that can reach a commit-time failure is two tabs each saving a new
-- plan at once: both take the insert path, both shift, both claim 0, and the second is abandoned
-- at COMMIT.
--
-- The backfill is ordered by `updated_at desc` so the list is unchanged the moment this lands, and
-- it runs with `plans_set_updated_at` **disabled**. The trigger is `new.updated_at = now()`
-- unconditionally, so without the disable the backfill would stamp every plan with this migration's
-- timestamp — reading it is safe either way (a window function sees the pre-statement snapshot) but
-- the stored values would be gone, and a phone not yet rebuilt still orders by them. **The disable
-- buys that order only until something writes a position**: the shift in `save_plan` below and every
-- reorder are ordinary updates of those rows, so they bump `updated_at` too, and the column stops
-- meaning "last edited" from the first new plan onward. Nothing reads it once both clients are
-- rebuilt — that is the whole point of this migration — and it is recorded here so that a future
-- reader finds it rather than infers it.
--
-- The block also makes the file re-runnable: pasted twice, the second paste finds the column and
-- skips the backfill rather than re-ranking the user's plans back to `updated_at` order.
--
-- NOTE: append-only, and `0014`'s `save_plan` is superseded by this one. Ninth definition.
--
-- ORDERING: the inverse of `0014`, and the milder direction. No client ever *sends* a
-- `plans.position` — `save_plan` computes it server-side, and the positions the web sends inside
-- the payload are the block and step ones, which it overwrites — so a stale deployed web bundle
-- saves exactly as it did before and nothing is wiped. What a stale client cannot do is *read* the
-- new order: both now order by a column that does not exist until this runs, and PostgREST answers
-- that with a 400 rather than an empty list, so **apply this before deploying the builder or
-- rebuilding the apps**.

do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'plans' and column_name = 'position'
       and is_nullable = 'NO'
  ) then
    raise notice 'plans.position already exists — leaving it and the backfill alone.';
    return;
  end if;

  -- The column exists but is not the shape this file leaves behind — hand-added, most likely, and
  -- a nullable position would let NULLs past the uniqueness rule below. Stop rather than guess.
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'plans' and column_name = 'position'
  ) then
    raise exception 'plans.position exists but is nullable — reconcile it by hand before running this';
  end if;

  -- The default exists only so the column can be added to a table that already has rows; it is
  -- dropped below, once every row has a real position.
  alter table public.plans
    add column position integer not null default 0
      constraint plans_position_check check (position >= 0);

  alter table public.plans disable trigger plans_set_updated_at;

  with ranked as (
    select id,
           (row_number() over (
              partition by user_id
              order by updated_at desc, created_at desc, id
            ) - 1)::int as pos
      from public.plans
  )
  update public.plans p
     set position = ranked.pos
    from ranked
   where p.id = ranked.id;

  alter table public.plans enable trigger plans_set_updated_at;

  alter table public.plans alter column position drop default;

  raise notice 'plans.position backfilled, in updated_at order.';
end;
$$;

alter table public.plans drop constraint if exists plans_user_position_key;
alter table public.plans
  add constraint plans_user_position_key
  unique (user_id, position) deferrable initially deferred;

-- ---------------------------------------------------------------------------
-- save_plan, ninth definition. Two changes, both about where a plan sits:
--
--   * a NEW plan goes to the top of its owner's list, so everything already there moves down one;
--   * an EDIT does not move it at all — `position` is absent from the `do update set` list, and a
--     conflicting tuple is never inserted, so the insert's value cannot reach a row that exists.
--
-- The shift runs only on the insert path, hence the existence test rather than a bare update.
-- It leans on the deferred constraint above for the same reason `reorder_plans` does: it rewrites
-- every position of the user's list in one statement.
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

  if not exists (select 1 from public.plans where id = v_plan_id and user_id = v_user) then
    update public.plans set position = position + 1 where user_id = v_user;
  end if;

  insert into public.plans (id, user_id, name, position)
  values (v_plan_id, v_user, payload->>'name', 0)
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
-- every case, and the migrations that redefine `save_plan` re-issue this line. (`0013` did not;
-- that is missing rather than deliberate, as `0014` records, and re-issuing it is harmless.)
grant execute on function public.save_plan(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- reorder_plans — the drag, as one statement.
--
-- The array IS the new order: index 0 is the top. `security invoker`, so RLS still applies and
-- this can never be a way around it — but that is also why both checks are explicit: an `update`
-- against another user's row matches nothing and says nothing, which is a silent no-op rather
-- than an error.
--
-- It is a whole-list operation on purpose. If a plan the caller did not name kept an old
-- position, the statement below would hand that number to another row, and the deferred constraint
-- would abandon the entire request at COMMIT — after this function had already returned void.
-- Counting rather than testing ids one by one also catches a repeated id, which would silently
-- shorten the list.
-- ---------------------------------------------------------------------------

create or replace function public.reorder_plans(p_ids uuid[])
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_named integer;
  v_mine  integer;
  v_all   integer;
begin
  if v_user is null then
    raise exception 'reorder_plans: not authenticated' using errcode = '28000';
  end if;

  v_named := coalesce(array_length(p_ids, 1), 0);
  if v_named = 0 then
    return;
  end if;

  select count(*) into v_mine
    from public.plans
   where user_id = v_user and id = any (p_ids);

  if v_mine <> v_named then
    raise exception 'reorder_plans: % of % ids are not this user''s plans, or are repeated',
      v_named - v_mine, v_named
      using errcode = '42501';
  end if;

  select count(*) into v_all from public.plans where user_id = v_user;

  if v_all <> v_named then
    raise exception 'reorder_plans: the list is not the whole list: % of % plans named',
      v_named, v_all
      using errcode = '22023';
  end if;

  update public.plans p
     set position = v.pos
    from (
      select id, (ordinality - 1)::int as pos
        from unnest(p_ids) with ordinality as t(id, ordinality)
    ) v
   where p.id = v.id;
end;
$$;

grant execute on function public.reorder_plans(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- What the column holds, as a result rather than a notice.
--
-- `out_of_order` is the one that means something: it re-derives the ranking the backfill used and
-- counts the rows that disagree with it, which is the only column here that compares a position
-- against the order it *should* have. The others are close to tautologies — the constraint added
-- above already guarantees positions are distinct, and `first_position = 0` alone would accept a
-- gappy 0,2,5.
-- ---------------------------------------------------------------------------

with ranked as (
  select id,
         (row_number() over (
            partition by user_id
            order by updated_at desc, created_at desc, id
          ) - 1)::int as expected
    from public.plans
)
select p.user_id,
       count(*)                                         as plans,
       count(*) filter (where p.position <> r.expected)  as out_of_order,
       min(p.position)                                  as first_position,
       max(p.position)                                  as last_position,
       count(distinct p.position)                       as distinct_positions
  from public.plans p
  join ranked r on r.id = p.id
 group by p.user_id;

-- `out_of_order` must be 0. No rows at all means the account has no plans yet, which is the same
-- result as a successful backfill of nothing — not a failure.
