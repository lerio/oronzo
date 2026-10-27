-- 0018 — workouts become the reusable tree; plans become weekly schedules.
--
-- Today's `plans` row is what you actually run, and `plan_blocks`/`plan_steps` are its tree.
-- Those become `workouts` / `workout_blocks` / `workout_steps`, and keep their ids, so history
-- and the phone's cache continue to point at the same rows. `plans` is then re-created as a
-- weekly template, and `plan_workouts` assigns a workout to a weekday (ISO 1 = Monday).
--
-- Three things here are deliberate and easy to get wrong:
--
--   * The old `save_plan`/`reorder_plans` are DROPPED before the renames. A PL/pgSQL body is
--     stored as text and is not rewritten by ALTER TABLE ... RENAME; leaving `save_plan` alive
--     would make it resolve `public.plans` to the *new* weekly table at execution time.
--   * Index/constraint names are schema-global while policies and triggers are per-table. The
--     old `plans_pkey`/`plans_user_position_key`/`plans_user_idx` must be renamed before the
--     new `plans` table is created, or `create table` fails on the duplicate name.
--   * `sessions.plan_id`/`plan_name` are deliberately NOT renamed. The FK follows the table
--     rename by OID, so the ids are still right, and an old iPhone build keeps writing history
--     during the cutover. A later migration can rename them once every client is installed.
--
-- Explicitly wrapped in one transaction: these renames are interdependent and a partial paste
-- leaves a schema nobody can reason about. Apply the whole file as one script.

begin;

-- ---------------------------------------------------------------------------
-- 1. Stop the old writers before their table names change meaning.
-- ---------------------------------------------------------------------------

drop function if exists public.save_plan(jsonb);
drop function if exists public.reorder_plans(uuid[]);

-- ---------------------------------------------------------------------------
-- 2. Rename the tree. Ids and rows survive.
-- ---------------------------------------------------------------------------

alter table public.plans       rename to workouts;
alter table public.plan_blocks rename to workout_blocks;
alter table public.workout_blocks rename column plan_id to workout_id;
alter table public.plan_steps  rename to workout_steps;

-- ---------------------------------------------------------------------------
-- 3. Free the schema-global names the new `plans` table needs.
--    (Constraint and index names are global; policy/trigger names are per-table.)
-- ---------------------------------------------------------------------------

alter table public.workouts rename constraint plans_pkey              to workouts_pkey;
alter table public.workouts rename constraint plans_user_id_fkey      to workouts_user_id_fkey;
alter table public.workouts rename constraint plans_position_check    to workouts_position_check;
alter table public.workouts rename constraint plans_user_position_key to workouts_user_position_key;
alter index public.plans_user_idx rename to workouts_user_idx;

-- ---------------------------------------------------------------------------
-- 4. Rename the child/cosmetic names. Policies and triggers follow the table OID and keep
--    working; the names are renamed only so errors and \d are readable.
-- ---------------------------------------------------------------------------

alter table public.workout_blocks rename constraint plan_blocks_pkey                  to workout_blocks_pkey;
alter table public.workout_blocks rename constraint plan_blocks_plan_id_fkey          to workout_blocks_workout_id_fkey;
alter table public.workout_blocks rename constraint plan_blocks_position_check        to workout_blocks_position_check;
alter table public.workout_blocks rename constraint plan_blocks_plan_id_position_key  to workout_blocks_workout_id_position_key;
alter index public.plan_blocks_plan_idx rename to workout_blocks_workout_idx;
alter trigger plan_blocks_set_updated_at on public.workout_blocks rename to workout_blocks_set_updated_at;
alter policy plan_blocks_all on public.workout_blocks rename to workout_blocks_all;

alter table public.workout_steps rename constraint plan_steps_pkey                 to workout_steps_pkey;
alter table public.workout_steps rename constraint plan_steps_block_id_fkey        to workout_steps_block_id_fkey;
alter table public.workout_steps rename constraint plan_steps_exercise_id_fkey     to workout_steps_exercise_id_fkey;
alter table public.workout_steps rename constraint plan_steps_position_check       to workout_steps_position_check;
alter table public.workout_steps rename constraint plan_steps_block_id_position_key to workout_steps_block_id_position_key;
alter table public.workout_steps rename constraint plan_steps_mode_shape           to workout_steps_mode_shape;
alter table public.workout_steps rename constraint plan_steps_sets_positive        to workout_steps_sets_positive;
alter index public.plan_steps_block_idx rename to workout_steps_block_idx;
alter index public.plan_steps_exercise_idx rename to workout_steps_exercise_idx;
alter trigger plan_steps_set_updated_at on public.workout_steps rename to workout_steps_set_updated_at;
alter policy plan_steps_all on public.workout_steps rename to workout_steps_all;

alter trigger plans_set_updated_at on public.workouts rename to workouts_set_updated_at;
alter policy plans_all on public.workouts rename to workouts_all;

-- The session columns keep their historical names on purpose. Say so in the database.
comment on column public.sessions.plan_id is
  'Historical name after 0018; references public.workouts(id).';
comment on column public.sessions.plan_name is
  'Historical name after 0018; snapshot of the workout name.';

-- ---------------------------------------------------------------------------
-- 5. New weekly plans. No position: plans are ordered by created_at, then name.
-- ---------------------------------------------------------------------------

create table public.plans (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null check (length(btrim(name)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index plans_user_idx on public.plans (user_id);

create trigger plans_set_updated_at
  before update on public.plans
  for each row execute function public.set_updated_at();

alter table public.plans enable row level security;

create policy plans_all on public.plans
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update, delete on public.plans to authenticated;

-- ---------------------------------------------------------------------------
-- 6. A scheduled occurrence. The triple is the identity: a workout can be on several days or
--    in several plans, but not twice on the same day of the same plan.
-- ---------------------------------------------------------------------------

create table public.plan_workouts (
  plan_id    uuid not null references public.plans (id) on delete cascade,
  workout_id uuid not null references public.workouts (id) on delete cascade,
  weekday    smallint not null check (weekday between 1 and 7),
  primary key (plan_id, workout_id, weekday)
);

-- The PK already indexes plan_id; this one serves workout deletes and lookups.
create index plan_workouts_workout_idx on public.plan_workouts (workout_id);

alter table public.plan_workouts enable row level security;

-- Every operation requires both the plan and the workout to be the caller's, so a known UUID
-- cannot attach someone else's workout — and a row is never visible through a plan alone.
create policy plan_workouts_all on public.plan_workouts
  for all to authenticated
  using (
    exists (
      select 1 from public.plans p
      where p.id = plan_workouts.plan_id and p.user_id = (select auth.uid())
    )
    and exists (
      select 1 from public.workouts w
      where w.id = plan_workouts.workout_id and w.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.plans p
      where p.id = plan_workouts.plan_id and p.user_id = (select auth.uid())
    )
    and exists (
      select 1 from public.workouts w
      where w.id = plan_workouts.workout_id and w.user_id = (select auth.uid())
    )
  );

grant select, insert, update, delete on public.plan_workouts to authenticated;

-- ---------------------------------------------------------------------------
-- 7. When the workout is best done. Null means "Anytime"; wall-clock, no timezone.
-- ---------------------------------------------------------------------------

alter table public.workouts add column preferred_time time;

comment on column public.workouts.preferred_time is
  'Wall-clock preference; null = anytime. No timezone, no notification semantics.';

-- ---------------------------------------------------------------------------
-- 8. save_workout — the ninth save_plan body, re-homed. Whole-tree replace, new block/step
--    ids on every save, insert-at-top for a new workout, and preferred_time on both paths.
-- ---------------------------------------------------------------------------

create or replace function public.save_workout(payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_workout_id uuid;
  v_block      jsonb;
  v_step       jsonb;
  v_block_id   uuid;
  v_block_pos  integer := 0;
  v_step_pos   integer;
begin
  if v_user is null then
    raise exception 'save_workout: not authenticated' using errcode = '28000';
  end if;

  v_workout_id := coalesce(nullif(payload->>'id', '')::uuid, gen_random_uuid());

  if not exists (
    select 1 from public.workouts where id = v_workout_id and user_id = v_user
  ) then
    update public.workouts set position = position + 1 where user_id = v_user;
  end if;

  insert into public.workouts (id, user_id, name, preferred_time, position)
  values (
    v_workout_id,
    v_user,
    payload->>'name',
    nullif(payload->>'preferred_time', '')::time,
    0
  )
  on conflict (id) do update
    set name = excluded.name,
        preferred_time = excluded.preferred_time
    where public.workouts.user_id = v_user;

  if not exists (
    select 1 from public.workouts where id = v_workout_id and user_id = v_user
  ) then
    raise exception 'save_workout: workout % not found for this user', v_workout_id
      using errcode = '42501';
  end if;

  delete from public.workout_blocks where workout_id = v_workout_id;

  for v_block in select * from jsonb_array_elements(coalesce(payload->'blocks', '[]'::jsonb))
  loop
    insert into public.workout_blocks (workout_id, position, name, rounds, rest_between_rounds_seconds)
    values (
      v_workout_id,
      v_block_pos,
      nullif(v_block->>'name', ''),
      coalesce((v_block->>'rounds')::int, 1),
      nullif(v_block->>'rest_between_rounds_seconds', '')::int
    )
    returning id into v_block_id;

    v_step_pos := 0;
    for v_step in select * from jsonb_array_elements(coalesce(v_block->'steps', '[]'::jsonb))
    loop
      insert into public.workout_steps (
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

  return v_workout_id;
end;
$$;

grant execute on function public.save_workout(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. reorder_workouts — the old reorder_plans against the renamed table.
-- ---------------------------------------------------------------------------

create or replace function public.reorder_workouts(p_ids uuid[])
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
    raise exception 'reorder_workouts: not authenticated' using errcode = '28000';
  end if;

  v_named := coalesce(array_length(p_ids, 1), 0);
  if v_named = 0 then
    return;
  end if;

  select count(*) into v_mine
    from public.workouts
   where user_id = v_user and id = any (p_ids);

  if v_mine <> v_named then
    raise exception 'reorder_workouts: % of % ids are not this user''s workouts, or are repeated',
      v_named - v_mine, v_named
      using errcode = '42501';
  end if;

  select count(*) into v_all from public.workouts where user_id = v_user;

  if v_all <> v_named then
    raise exception 'reorder_workouts: the list is not the whole list: % of % workouts named',
      v_named, v_all
      using errcode = '22023';
  end if;

  update public.workouts w
     set position = v.pos
    from (
      select id, (ordinality - 1)::int as pos
        from unnest(p_ids) with ordinality as t(id, ordinality)
    ) v
   where w.id = v.id;
end;
$$;

grant execute on function public.reorder_workouts(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. There is deliberately no weekly save_plan RPC. The builder writes one row at a time
--     (insert/delete plan_workouts, update plans.name), so a stale tab cannot overwrite a
--     whole week and there is no whole-plan payload to validate.
-- ---------------------------------------------------------------------------

notify pgrst, 'reload schema';

commit;
