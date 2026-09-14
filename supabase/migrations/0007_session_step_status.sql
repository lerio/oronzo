-- Let history distinguish "I skipped this" from "I never got to this".
--
-- The engine already reports `.notReached` for intervals the session ended before, and
-- recording those as 'skipped' would quietly claim you chose to skip something you simply
-- ran out of time for. The distinction matters when reading back a session that was cut
-- short.

alter table public.session_steps
  drop constraint if exists session_steps_status_check;

alter table public.session_steps
  add constraint session_steps_status_check
  check (status in ('pending', 'completed', 'skipped', 'not_reached'));

comment on column public.session_steps.status is
  'completed = done; skipped = deliberately passed over; not_reached = the session ended first.';
