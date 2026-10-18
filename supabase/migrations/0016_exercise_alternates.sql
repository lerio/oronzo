-- `alternates_sides`: whether an exercise is performed on both sides *alternately*.
--
-- `0012` gave an exercise one way to be unilateral: left, then right, as two intervals per set.
-- That cannot express the movement you actually alternate — a walking lunge, a single-arm row, a
-- dead bug — where ten left and then ten right is a *different exercise* from twenty alternating
-- ones. So this is a third behaviour rather than a relabelling of the second, and the two are
-- mutually exclusive: a row claiming both would emit a left/right pair *and* an "alternating"
-- marker, which describes nothing.
--
-- It lives on the exercise for the reason `has_two_sides` does: it is a property of the movement,
-- not of the prescription. Consequences worth knowing:
--
--   * **No flattener loop change, and no change to the interval stream at all.** An alternating
--     exercise is simply *not* two-sided, so `PlanFlattener.sideSuffixes` already returns `[nil]`
--     for it — one interval per set, with the rest and any "Get in position" falling once. The
--     whole of the new behaviour is a word appended to the interval's `name`, which is where the
--     side suffix goes too. Nothing is added to `Interval`, so the phone↔watch wire format,
--     `SessionRecord` and `PlanCache` are all untouched.
--   * **The step's rep count means the total, not the per-side number.** `has_two_sides` reads
--     "8 reps" as eight *each*, where alternating reads "20 reps" as twenty *altogether* — the
--     count is emitted once, so `PlanSummary` counts it once. This is the one thing about the
--     feature that is easy to get wrong later; `docs/integration-contracts.md` says it again.
--   * No column on `plan_steps`, so `save_plan` is untouched, and neither of the *plan* select
--     strings changes. The **exercise** fetch does: `PlanRepository` selects the new column.
--
-- Existing rows default to false, so nothing that runs today changes because of this file.
--
-- **Ordering.** Same rule as `0012`: the iOS build that ships alongside this selects
-- `alternates_sides`, and a select naming a column the database does not have is a `400` on the
-- device — `PlanStore.refresh()` then keeps whatever the cache holds and says so in a banner. The
-- web bundle names the column on insert, which is a `400` too. Apply this before deploying either
-- client. (Not "on a cold start it says No plans yet", which `0012` claimed and
-- `docs/known-issues.md` §3 has since closed: `PlanListView` now branches on `store.error` before
-- the empty state and offers "Try again".)

alter table public.exercises
  add column if not exists alternates_sides boolean not null default false;

alter table public.exercises
  drop constraint if exists exercises_sides_shape;

-- Both columns are NOT NULL, which is what makes this a real check: against a NULL either side,
-- the conjunction would be NULL and the constraint would let the row through.
alter table public.exercises
  add constraint exercises_sides_shape check (not (has_two_sides and alternates_sides));

-- ---------------------------------------------------------------------------
-- What is left, as a result rather than a notice.
-- ---------------------------------------------------------------------------

select
  count(*)                                  as exercises,
  count(*) filter (where has_two_sides)     as two_sided,
  count(*) filter (where alternates_sides)  as alternating;
