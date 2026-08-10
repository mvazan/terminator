-- Připomínky startů v Google kalendáři si každý řídí sám z Nastavení.
--
-- Mechanika: NEzapisujeme připomínky do jednotlivých událostí, ale jako
-- default celého kalendáře „Termínátor" (calendarList.defaultReminders —
-- per-uživatelské nastavení kalendáře). Události je dědí, takže změna
-- preference se okamžitě projeví na VŠECH startech včetně už založených,
-- bez přepisování událostí. Aplikuje ji server jobem `calendar_reminders`
-- na enginu z 0025 (debounce: rychlé přepínání = jeden job s poslední
-- hodnotou, revalidace: handler si preferenci přečte až při běhu).
--
-- Výchozí stav je ŽÁDNÁ připomínka: nový kalendář z API žádné defaulty
-- nemá a callback už je nenastavuje (dřívější napevno „den + 2 h" bylo
-- vlastnické rozhodnutí appky, které si nikdo nevybral). Řádky z doby před
-- touto migrací dostávají '1d2h' — jejich kalendáře ty defaulty reálně
-- mají, ať appka ukazuje pravdu.

alter table google_calendar_links add column reminders text not null
  default 'none' check (reminders in ('none', '2h', '1d', '1d2h'));

update google_calendar_links set reminders = '1d2h';

/** Uloží preferenci připomínek a naplánuje její propsání do Googlu.
 * run_at = now(): minutový cron ji vezme do ~minuty; mezitím dlaždice
 * ukazuje novou hodnotu z tabulky (stream), takže UI nečeká na Google. */
create or replace function set_calendar_reminders(p_pref text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_pref not in ('none', '2h', '1d', '1d2h') then
    raise exception 'bad_pref';
  end if;
  update google_calendar_links
    set reminders = p_pref, updated_at = now()
    where user_id = auth.uid();
  if not found then
    raise exception 'not_linked';
  end if;
  perform enqueue_notification('calendar_reminders',
    'calendar_reminders:' || auth.uid(),
    jsonb_build_object('user_id', auth.uid()),
    interval '0 seconds');
end;
$$;
revoke execute on function set_calendar_reminders(text) from public;
grant execute on function set_calendar_reminders(text) to authenticated;
