-- Venue-cancelled starts. When a scraped slot vanishes from the organizer's
-- reservation page, the app stamps cancelled_at instead of deleting the row:
-- a delete would cascade into availability (the very people the notification
-- is for) and order_slots (silently shrinking orders). Cancelled slots are
-- hidden from pickers and the season calendar; if the page lists the start
-- again, the app clears the stamp and the slot revives with its ticks.
alter table slots add column cancelled_at timestamptz;

-- Producer (NOTIFICATIONS.md, deferred engine 0025): the null→set transition
-- enqueues one slots_cancelled job per tournament+day — the dedupe key folds
-- every start cancelled that day into a single push. Revive is the undo: it
-- dequeues, but only when no other start of that day remains cancelled
-- (a partial restore must still notify about the rest). The handler in the
-- notify EF revalidates at send time and stays silent when nothing is
-- cancelled anymore.
create or replace function slots_enqueue_jobs()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_key text := 'slots_cancelled:' || new.tournament_id || ':' || new.date;
begin
  if old.cancelled_at is null and new.cancelled_at is not null then
    perform enqueue_notification('slots_cancelled', v_key,
      jsonb_build_object('tournament_id', new.tournament_id,
                         'date', new.date));
  elsif old.cancelled_at is not null and new.cancelled_at is null then
    if not exists (
      select 1 from slots
       where tournament_id = new.tournament_id
         and date = new.date
         and cancelled_at is not null
         and id <> new.id
    ) then
      perform dequeue_notification(v_key);
    end if;
  end if;
  return new;
end;
$$;

create trigger slots_enqueue_jobs
  after update on slots
  for each row
  when (old.cancelled_at is distinct from new.cancelled_at)
  execute function slots_enqueue_jobs();
