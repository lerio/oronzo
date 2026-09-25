-- `has_two_sides`: whether an exercise is performed once per side.
--
-- Unilateral work — a reverse lunge, a single-arm row, a side plank — is done left, then right.
-- Until now the only way to say so was a step note, and `0008_drop_notes_and_actuals.sql` deleted
-- that channel because iOS decoded notes and threw them away. So the builder could ask for
-- "8 reps per leg" while nothing in the system knew it was per leg: one interval, and the other
-- side was something you had to remember mid-workout.
--
-- The flag lives on the exercise, not on the plan step, because it is a property of the movement
-- rather than of the prescription. `PlanFlattener` reads it while flattening and emits each set
-- twice — left, then right, then the rest the step already asks for. Consequences worth knowing:
--
--   * No column on `plan_steps`, so `save_plan` is untouched (it has already been redefined six
--     times) and neither of the *plan* select strings — `PlanRepository.planSelect` and
--     `api.ts` PLAN_SELECT — changes. The exercise fetch does change; see the note below.
--   * No field on `Interval`, so nothing on the phone↔watch wire changes: the side is carried in
--     the interval's `name`, which both surfaces already draw. An added field would not have
--     *broken* decoding — `Interval` decodes optionals with `decodeIfPresent` — but it would be a
--     format two separately-installed apps have to agree on, for text that only ever appears in
--     one place. (`docs/decisions.md` records the trade and the escape hatch.)
--
-- Existing rows default to false, so nothing that runs today starts doubling because of this file.
--
-- **Ordering, from here on:** `0011` could claim that dropping a column was safe for the phone
-- because iOS fetched exercises with `.select("id,name")`. That stops being true with this file.
-- The iOS build that ships alongside `0012` selects `has_two_sides`, so the column has to exist
-- before that build runs, or every plan fetch is a `400` on the device — `PlanStore.refresh()`
-- then keeps whatever the cache holds and says so in a banner, and on a cold start with no cache
-- it says "No plans yet" instead. Apply this migration before building the app.

alter table public.exercises
  add column has_two_sides boolean not null default false;

-- ---------------------------------------------------------------------------
-- What is left, as a result rather than a notice.
-- ---------------------------------------------------------------------------

select
  count(*)                              as exercises,
  count(*) filter (where has_two_sides) as two_sided;
