-- Oronzo — initial schema.
--
-- Model in one sentence: a plan is an ordered list of *blocks*, each repeating its
-- ordered list of *steps* `rounds` times. A step is exactly ONE interval — either a
-- timed step (auto-advance) or a rep-based step (tap to advance) or an explicit rest.
--
-- That single primitive expresses every shape we need:
--   "3x12 squats, 90s between sets"  -> one block, rounds=3,
--                                       rest_between_rounds_seconds=90, one rep step
--   "circuit of 4 x 3 rounds, 20s"   -> one block, rounds=3, four steps each with
--                                       rest_after_seconds=20
--
-- Flattening rule (identical in the web preview, the iOS engine and the Watch):
--   for block in blocks ordered by position:
--     for round in 1..block.rounds:
--       for step in steps ordered by position:
--         emit step; if step.rest_after_seconds: emit rest
--       if round < block.rounds and block.rest_between_rounds_seconds: emit rest
--
-- NOTE the deliberate asymmetry: `rest_after_seconds` DOES fire after the final step of
-- a round (usually what you want — it doubles as the rest before the next round), while
-- `rest_between_rounds_seconds` only fires BETWEEN rounds.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- exercises — seeded rows (user_id IS NULL, identified by slug) + user-created ones
-- ---------------------------------------------------------------------------

create table public.exercises (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid references auth.users (id) on delete cascade,
  slug                     text,
  name                     text not null check (length(btrim(name)) > 0),
  muscle_group             text not null default 'full_body',
  equipment                text not null default 'bodyweight',
  default_mode             text not null default 'reps' check (default_mode in ('time', 'reps')),
  default_duration_seconds integer check (default_duration_seconds > 0),
  default_reps             integer check (default_reps > 0),
  notes                    text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  -- A seeded row has a slug and no owner; a custom row has an owner and no slug.
  constraint exercises_seed_shape check (
    (user_id is null and slug is not null)
    or (user_id is not null and slug is null)
  ),
  -- Time-based exercises must declare a duration.
  constraint exercises_mode_shape check (
    default_mode <> 'time' or default_duration_seconds is not null
  )
);

-- Deliberately NOT partial: custom rows have slug = NULL, and NULLs never collide in a
-- unique index. Keeping it non-partial lets the seed use a plain `on conflict (slug)`.
create unique index exercises_slug_key on public.exercises (slug);
create unique index exercises_user_name_key on public.exercises (user_id, lower(name)) where user_id is not null;
create index exercises_user_idx on public.exercises (user_id);

create trigger exercises_set_updated_at
  before update on public.exercises
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- plans -> blocks -> steps
-- ---------------------------------------------------------------------------

create table public.plans (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null check (length(btrim(name)) > 0),
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index plans_user_idx on public.plans (user_id);

create trigger plans_set_updated_at
  before update on public.plans
  for each row execute function public.set_updated_at();

create table public.plan_blocks (
  id                           uuid primary key default gen_random_uuid(),
  plan_id                      uuid not null references public.plans (id) on delete cascade,
  position                     integer not null check (position >= 0),
  name                         text,
  rounds                       integer not null default 1 check (rounds >= 1),
  rest_between_rounds_seconds  integer check (rest_between_rounds_seconds >= 0),
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),
  unique (plan_id, position)
);

create index plan_blocks_plan_idx on public.plan_blocks (plan_id);

create trigger plan_blocks_set_updated_at
  before update on public.plan_blocks
  for each row execute function public.set_updated_at();

create table public.plan_steps (
  id                uuid primary key default gen_random_uuid(),
  block_id          uuid not null references public.plan_blocks (id) on delete cascade,
  -- ON DELETE RESTRICT, not SET NULL: silently emptying a step out of a live plan is a
  -- worse failure than telling the user "this exercise is used by 2 plans".
  exercise_id       uuid references public.exercises (id) on delete restrict,
  position          integer not null check (position >= 0),
  kind              text not null default 'exercise' check (kind in ('exercise', 'rest')),
  label             text,
  mode              text not null default 'reps' check (mode in ('time', 'reps')),
  duration_seconds  integer check (duration_seconds > 0),
  reps              integer check (reps > 0),
  target_weight_kg  numeric(6, 2) check (target_weight_kg >= 0),
  rest_after_seconds integer check (rest_after_seconds >= 0),
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (block_id, position),

  constraint plan_steps_shape check (
    case
      -- An explicit rest is always a timed interval.
      when kind = 'rest' then mode = 'time' and duration_seconds is not null
      -- An exercise is timed with a duration, or rep-based with a target.
      else (mode = 'time' and duration_seconds is not null)
        or (mode = 'reps' and reps is not null)
    end
  ),
  -- An exercise step must reference an exercise.
  constraint plan_steps_exercise_required check (kind <> 'exercise' or exercise_id is not null)
);

create index plan_steps_block_idx on public.plan_steps (block_id);
create index plan_steps_exercise_idx on public.plan_steps (exercise_id);

create trigger plan_steps_set_updated_at
  before update on public.plan_steps
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- sessions — what actually happened. Snapshots names and planned values so that
-- history survives later edits or deletion of the plan and the exercises.
-- ---------------------------------------------------------------------------

create table public.sessions (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references auth.users (id) on delete cascade,
  plan_id                uuid references public.plans (id) on delete set null,
  plan_name              text not null,
  started_at             timestamptz not null,
  finished_at            timestamptz,
  status                 text not null default 'in_progress'
                           check (status in ('in_progress', 'completed', 'abandoned')),
  total_duration_seconds integer check (total_duration_seconds >= 0),
  notes                  text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),

  constraint sessions_finished_shape check (
    (status = 'in_progress' and finished_at is null)
    or (status <> 'in_progress' and finished_at is not null)
  )
);

create index sessions_user_started_idx on public.sessions (user_id, started_at desc);
create index sessions_plan_idx on public.sessions (plan_id);

create trigger sessions_set_updated_at
  before update on public.sessions
  for each row execute function public.set_updated_at();

create table public.session_steps (
  id                      uuid primary key default gen_random_uuid(),
  session_id              uuid not null references public.sessions (id) on delete cascade,
  position                integer not null check (position >= 0),
  round_index             integer check (round_index >= 1),
  block_name              text,
  kind                    text not null check (kind in ('exercise', 'rest')),
  exercise_id             uuid references public.exercises (id) on delete set null,
  exercise_name           text not null,
  planned_mode            text check (planned_mode in ('time', 'reps')),
  planned_duration_seconds integer,
  planned_reps            integer,
  planned_weight_kg       numeric(6, 2),
  actual_duration_seconds integer check (actual_duration_seconds >= 0),
  actual_reps             integer check (actual_reps >= 0),
  actual_weight_kg        numeric(6, 2) check (actual_weight_kg >= 0),
  status                  text not null default 'pending'
                            check (status in ('pending', 'completed', 'skipped')),
  created_at              timestamptz not null default now(),
  unique (session_id, position)
);

create index session_steps_session_idx on public.session_steps (session_id);
create index session_steps_exercise_idx on public.session_steps (exercise_id);

-- ---------------------------------------------------------------------------
-- Row Level Security — single user, but enforced in the database, not the client.
-- `(select auth.uid())` is Supabase's recommended form: it is evaluated once per
-- query rather than once per row.
-- ---------------------------------------------------------------------------

alter table public.exercises     enable row level security;
alter table public.plans         enable row level security;
alter table public.plan_blocks   enable row level security;
alter table public.plan_steps    enable row level security;
alter table public.sessions      enable row level security;
alter table public.session_steps enable row level security;

-- exercises: anyone signed in may READ the seeded library; you may only write your own.
create policy exercises_select on public.exercises
  for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));

create policy exercises_insert on public.exercises
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy exercises_update on public.exercises
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy exercises_delete on public.exercises
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- plans
create policy plans_all on public.plans
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- blocks: authorised through their parent plan. The predicate is written out
-- explicitly rather than relying on the nested RLS of `plans`.
create policy plan_blocks_all on public.plan_blocks
  for all to authenticated
  using (
    exists (
      select 1 from public.plans p
      where p.id = plan_blocks.plan_id and p.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.plans p
      where p.id = plan_blocks.plan_id and p.user_id = (select auth.uid())
    )
  );

-- steps: authorised through block -> plan.
create policy plan_steps_all on public.plan_steps
  for all to authenticated
  using (
    exists (
      select 1
      from public.plan_blocks b
      join public.plans p on p.id = b.plan_id
      where b.id = plan_steps.block_id and p.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.plan_blocks b
      join public.plans p on p.id = b.plan_id
      where b.id = plan_steps.block_id and p.user_id = (select auth.uid())
    )
  );

-- sessions
create policy sessions_all on public.sessions
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy session_steps_all on public.session_steps
  for all to authenticated
  using (
    exists (
      select 1 from public.sessions s
      where s.id = session_steps.session_id and s.user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.sessions s
      where s.id = session_steps.session_id and s.user_id = (select auth.uid())
    )
  );

-- Supabase grants privileges on new public tables to `authenticated` by default, but
-- relying on that leaves a confusing "permission denied for table" if the defaults are
-- ever absent. Stating them makes the intent explicit. `anon` deliberately gets NOTHING —
-- combined with RLS being enabled and every policy being `to authenticated`, an
-- unauthenticated request can read and write nothing at all.
grant select, insert, update, delete on public.exercises     to authenticated;
grant select, insert, update, delete on public.plans         to authenticated;
grant select, insert, update, delete on public.plan_blocks   to authenticated;
grant select, insert, update, delete on public.plan_steps    to authenticated;
grant select, insert, update, delete on public.sessions      to authenticated;
grant select, insert, update, delete on public.session_steps to authenticated;

-- ---------------------------------------------------------------------------
-- save_plan — write a whole plan (blocks + steps) atomically.
--
-- A plan save touches 1 + N + M rows. Doing that as a sequence of client calls risks
-- a half-saved plan if one call fails; this makes it one transaction.
-- `security invoker` means RLS still applies to every statement.
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
    -- Never let a mismatched id adopt someone else's plan.
    where public.plans.user_id = v_user;

  if not exists (select 1 from public.plans where id = v_plan_id and user_id = v_user) then
    raise exception 'save_plan: plan % not found for this user', v_plan_id using errcode = '42501';
  end if;

  -- Replace the structure wholesale: simpler and safer than diffing, and sessions do
  -- not reference plan structure (they snapshot it), so nothing else can dangle.
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
