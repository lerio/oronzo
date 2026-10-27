-- 0019 — seed a weekly plan from the old named-by-weekday rows.
--
-- `0018` turned every old plan into a standalone workout. This is the one convenience pass:
-- create a `My week` plan per user and schedule the workouts whose names begin with a full
-- English weekday. The three existing seeds are exactly that shape:
--
--   Monday — Upper Body A + HIIT
--   Tuesday — Lower Body A
--   Thursday — Upper Body B + HIIT
--
-- The inference is deliberately narrow: the first space-delimited token, lowercased, must be a
-- full weekday name. It does not understand `Mon`, `Leg day`, emoji, or free text. That is fine:
-- this only seeds an editable plan, and every decision is printed as a notice plus a final count.
-- Anything unmatched stays in the workout library.
--
-- Idempotent enough to re-run: an existing `My week` is reused, and membership inserts ignore
-- conflicts. Workout ids are untouched, so `sessions.plan_id` still points at the same rows.

do $$
declare
  u            record;
  w            record;
  v_plan_id    uuid;
  v_weekday    smallint;
  v_scheduled  integer;
  v_standalone integer;
begin
  for u in select id from auth.users loop
    if not exists (select 1 from public.workouts where user_id = u.id) then
      continue;
    end if;

    if not exists (
      select 1 from public.plans where user_id = u.id and name = 'My week'
    ) then
      insert into public.plans (user_id, name)
      values (u.id, 'My week')
      returning id into v_plan_id;
    else
      select id into v_plan_id
        from public.plans
       where user_id = u.id and name = 'My week'
       order by created_at, id
       limit 1;
    end if;

    v_scheduled := 0;
    v_standalone := 0;

    for w in
      select id, name from public.workouts where user_id = u.id order by position
    loop
      v_weekday := case lower(split_part(btrim(w.name), ' ', 1))
        when 'monday'    then 1
        when 'tuesday'   then 2
        when 'wednesday' then 3
        when 'thursday'  then 4
        when 'friday'    then 5
        when 'saturday'  then 6
        when 'sunday'    then 7
        else null
      end;

      if v_weekday is null then
        v_standalone := v_standalone + 1;
        raise notice 'standalone: %', w.name;
      else
        insert into public.plan_workouts (plan_id, workout_id, weekday)
        values (v_plan_id, w.id, v_weekday)
        on conflict (plan_id, workout_id, weekday) do nothing;
        v_scheduled := v_scheduled + 1;
        raise notice 'scheduled on %: %', v_weekday, w.name;
      end if;
    end loop;

    raise notice 'user %: plan %, % scheduled, % standalone',
      u.id, v_plan_id, v_scheduled, v_standalone;
  end loop;
end;
$$;

-- The result, as rows rather than only notices.
select p.user_id, p.name, count(pw.*) as workouts
  from public.plans p
  left join public.plan_workouts pw on pw.plan_id = p.id
 group by p.user_id, p.id, p.name
 order by p.user_id, p.name;

select w.user_id,
       count(*) as workouts,
       count(*) filter (where pw.workout_id is null) as standalone
  from public.workouts w
  left join public.plan_workouts pw on pw.workout_id = w.id
 group by w.user_id;
