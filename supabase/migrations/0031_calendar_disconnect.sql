-- Odpojení SMAŽE kalendář „Termínátor" z Googlu — jinak se hromadí.
--
-- Empiricky ověřeno proti API (2026-08-10): pod scope calendar.app.created
-- je calendarList.list zakázaný (403) a calendars.get na kalendář ze
-- staršího grantu vrací 404 — po odvolání souhlasu se appka ke „svému"
-- dřívějšímu kalendáři už NIKDY nedostane. Znovupoužití (0027's
-- findAppCalendar) tedy nemohlo fungovat a každé re-propojení zakládalo
-- další kalendář. Jediný čistý návrh: smazat kalendář v okamžiku odpojení,
-- dokud token ještě žije. Starty jsou odvozená data — nové propojení je
-- backfillem nahraje do čistého kalendáře znovu.
--
-- Mazání potřebuje OAuth access token (refresh přes Google), což SQL neumí —
-- dělá to job `calendar_disconnect` v notify EF. RPC tady jen přepne stav
-- a job zařadí; řádky maže až handler (do té doby drží token).

alter table google_calendar_links drop constraint google_calendar_links_status_check;
alter table google_calendar_links add constraint google_calendar_links_status_check
  check (status in ('pending', 'linked', 'broken', 'disconnecting'));
-- 'disconnecting' klienti neznají a parse fallback ho čte jako notLinked —
-- dlaždice tedy hned nabízí „Propojit", i na starých buildech.

create or replace function disconnect_calendar()
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update google_calendar_links
    set status = 'disconnecting', updated_at = now()
    where user_id = auth.uid();
  if not found then
    raise exception 'not_linked';
  end if;
  perform enqueue_notification('calendar_disconnect',
    'calendar_disconnect:' || auth.uid(),
    jsonb_build_object('user_id', auth.uid()),
    interval '0 seconds');
end;
$$;
revoke execute on function disconnect_calendar() from public;
grant execute on function disconnect_calendar() to authenticated;
