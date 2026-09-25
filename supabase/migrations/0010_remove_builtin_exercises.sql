-- Remove the seeded exercise library.
--
-- `0002_seed_exercises.sql` and `0009_seed_more_exercises.sql` installed ~122 rows owned by
-- nobody (`user_id IS NULL`, identified by `slug`), shown in the app as a read-only "Library".
-- Every one of them goes. What is left is the exercises the user created — the whole list
-- editable and deletable.
--
-- Two consequences, both deliberate:
--
--   * `plan_steps.exercise_id` is ON DELETE RESTRICT, so a plan step cannot be left *orphaned*
--     by this; it can only be *deleted*. Steps pointing at a seeded exercise are therefore
--     removed below, which shortens those plans. That is the chosen trade: the alternative was
--     leaving the rows alive but hidden, which is the thing being removed. Every step this
--     drops is named in the output first.
--   * A block whose steps were all seeded is left in place, empty, rather than deleted. The
--     block is the user's own writing — its name, its rounds, its rest — and only its *steps*
--     came from the library. Empty blocks are listed below, and it is one click to remove one
--     in the builder.
--
-- `session_steps` is untouched and loses nothing: its `exercise_id` is ON DELETE SET NULL, and
-- `exercise_name` is snapshotted onto the row, so history still reads correctly.
--
-- NOTE: migrations are append-only, so `0002` and `0009` stay exactly as written. A database
-- rebuilt from empty seeds them and then this file removes them again — the same end state, and
-- the record of what the library contained stays readable.

-- ---------------------------------------------------------------------------
-- Say what this costs, before it costs it.
-- ---------------------------------------------------------------------------

do $report$
declare
  v_exercises integer;
  v_steps     integer;
  rec         record;
begin
  select count(*) into v_exercises from public.exercises where user_id is null;

  select count(*) into v_steps
    from public.plan_steps ps
    join public.exercises e on e.id = ps.exercise_id
   where e.user_id is null;

  raise notice 'Seeded library: % exercise(s). Plan steps referencing them: %.', v_exercises, v_steps;

  for rec in
    select p.name as plan_name,
           b.name as block_name,
           coalesce(nullif(btrim(ps.label), ''), e.name) as step_name,
           e.name as exercise_name
      from public.plan_steps ps
      join public.exercises e on e.id = ps.exercise_id
      join public.plan_blocks b on b.id = ps.block_id
      join public.plans p on p.id = b.plan_id
     where e.user_id is null
     order by p.name, b.position, ps.position
  loop
    raise notice '  DELETING step  % / % / %   (was the built-in "%")',
      rec.plan_name, coalesce(rec.block_name, 'unnamed block'), rec.step_name, rec.exercise_name;
  end loop;

  -- Blocks that lose every step they had. Their remaining content is the user's, so they stay.
  for rec in
    select p.name as plan_name, b.name as block_name
      from public.plan_blocks b
      join public.plans p on p.id = b.plan_id
     where exists (select 1 from public.plan_steps ps where ps.block_id = b.id)
       and not exists (
         select 1
           from public.plan_steps ps
           join public.exercises e on e.id = ps.exercise_id
          where ps.block_id = b.id
            and e.user_id is not null
       )
     order by p.name, b.position
  loop
    raise notice '  block left EMPTY (kept):  % / %', rec.plan_name, coalesce(rec.block_name, 'unnamed block');
  end loop;
end;
$report$;

-- ---------------------------------------------------------------------------
-- The deletion. Steps first — they are what holds the RESTRICT back.
-- ---------------------------------------------------------------------------

delete from public.plan_steps ps
 using public.exercises e
 where ps.exercise_id = e.id
   and e.user_id is null;

-- The surviving positions are now gapped (0, 2, 5 …). Compacting them keeps the stored tree
-- canonical instead of leaving holes that only the next save from the builder would close.
--
-- The +1000000 first is not belt-and-braces: `unique (block_id, position)` is enforced per row
-- as the UPDATE runs, in no guaranteed order, so compacting {1, 2} -> {0, 1} can land a row on a
-- position that a row which has not moved yet still holds.
update public.plan_steps set position = position + 1000000;

with renumbered as (
  select id,
         row_number() over (partition by block_id order by position) - 1 as new_position
    from public.plan_steps
)
update public.plan_steps ps
   set position = r.new_position
  from renumbered r
 where r.id = ps.id;

-- `user_id is null` is exactly the seeded set: `exercises_seed_shape` guarantees a row is either
-- unowned *with* a slug or owned without one.
delete from public.exercises where user_id is null;

-- ---------------------------------------------------------------------------
-- What is left, as a result rather than a notice — the last statement's grid is what the SQL
-- editor puts in front of you, and this is the line worth reading.
-- ---------------------------------------------------------------------------

select
  (select count(*) from public.exercises where user_id is null)     as built_in_exercises_left,
  (select count(*) from public.exercises where user_id is not null) as your_exercises_left,
  (select count(*) from public.plan_steps)                          as plan_steps_left;
