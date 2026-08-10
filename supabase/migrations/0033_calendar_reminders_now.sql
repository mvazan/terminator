-- Změna připomínek okamžitě, ne za dvě otočky cronu.
--
-- Připomínky nesou samotné události (calendarList je pod scope
-- calendar.app.created zakázaný), takže „změnit připomínku" znamená přepsat
-- budoucí starty. Přes joby to šlo dvěma skoky — RPC zařadila
-- `calendar_reminders`, minutový cron ho proměnil v `calendar_sync` joby a
-- ty čekaly na další cron. Dvě minuty, ve kterých to vypadá rozbitě.
--
-- Nově to udělá EF calendar-manage synchronně a potřebuje k tomu dvě věci:
-- uložit preferenci JMÉNEM uživatele (EF jede pod service_role, takže
-- auth.uid() je null) a přečíst si jeho budoucí starty i s podklady pro
-- událost. Job cesta zůstává jako záchranná síť a pro buildy <= 55.

/** Totéž co set_calendar_reminders(int[]), jen pro daného uživatele —
 * validaci i normalizaci nechává na ní, ať je pravidlo na jednom místě.
 * Bez enqueue: volající (EF) přepisuje události sám. */
create or replace function set_calendar_reminders_for(
  p_user_id uuid, p_minutes int[])
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_minutes int[];
begin
  select coalesce(array_agg(distinct m order by m desc), '{}'::int[])
    into v_minutes
    from unnest(coalesce(p_minutes, '{}'::int[])) as m;
  if array_length(v_minutes, 1) > 5 or
     exists (select 1 from unnest(v_minutes) m where m < 0 or m > 40320) then
    raise exception 'bad_reminders';
  end if;
  update google_calendar_links
    set reminder_minutes = v_minutes, updated_at = now()
    where user_id = p_user_id;
  if not found then
    raise exception 'not_linked';
  end if;
end;
$$;
revoke execute on function set_calendar_reminders_for(uuid, int[]) from public;
grant execute on function set_calendar_reminders_for(uuid, int[]) to service_role;

/** Budoucí starty uživatele i s tím, co patří do události. Stejná definice
 * „reálného startu" jako backfill_calendar_jobs: roster ∩ aktivní objednávka
 * ∩ datum od dneška. */
create or replace function my_future_starts(p_user_id uuid)
-- Sloupce se jmenují jinak než v tabulkách: `date`/`time` jsou v hlavičce
-- RETURNS TABLE klíčová slova a parser je odmítne.
returns table (
  slot_id uuid,
  start_date date,
  start_time time,
  tournament_name text,
  kind text,
  discipline text,
  notes text,
  venue_name text,
  venue_address text
)
language sql security definer set search_path = public
as $$
  select distinct s.id, s.date, s.time,
         t.name, t.kind, t.discipline, t.notes, v.name, v.address
    from rosters r
    join slots s on s.id = r.slot_id
    join order_slots os on os.slot_id = s.id
    join orders o on o.id = os.order_id
    join tournaments t on t.id = s.tournament_id
    left join venues v on v.id = t.venue_id
    where r.user_id = p_user_id
      and o.status in ('ordered', 'confirmed')
      and s.date >= current_date;
$$;
revoke execute on function my_future_starts(uuid) from public;
grant execute on function my_future_starts(uuid) to service_role;
