-- Připomínky bez předvoleb: uživatel si zadá vlastní „kolik minut/hodin/dní
-- předem", až 5 připomínek (limit Googlu). Enum ze včerejška (0029) byl moc
-- těsný — místo něj pole minut, tedy PŘESNĚ tvar, který bere Calendar API
-- (defaultReminders[].minutes), žádné mapování mezi vrstvami.
--
-- Google limity: max 5 připomínek, každá 0–40320 minut (4 týdny) předem.

alter table google_calendar_links add column reminder_minutes int[]
  not null default '{}';

update google_calendar_links set reminder_minutes = case reminders
  when '2h'   then '{120}'::int[]
  when '1d'   then '{1440}'::int[]
  when '1d2h' then '{1440,120}'::int[]
  else '{}'::int[]
end;

alter table google_calendar_links drop column reminders;

/** Uloží připomínky (minuty před startem) a naplánuje propsání do Googlu.
 * Normalizace distinct+sort desc: „den a 2 h" je totéž pole bez ohledu na
 * pořadí zadání, a UI i Google je ukazují od nejvzdálenější. */
create or replace function set_calendar_reminders(p_minutes int[])
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
revoke execute on function set_calendar_reminders(int[]) from public;
grant execute on function set_calendar_reminders(int[]) to authenticated;

-- Kompatibilní obal pro buildy 2.6.0 (posílají p_pref s předvolbou) — jen
-- přeloží předvolbu na minuty. PostgREST obě přetížení rozliší podle jména
-- parametru. Zahodit, až min_build překročí 53.
create or replace function set_calendar_reminders(p_pref text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_pref not in ('none', '2h', '1d', '1d2h') then
    raise exception 'bad_reminders';
  end if;
  perform set_calendar_reminders(case p_pref
    when '2h'   then '{120}'::int[]
    when '1d'   then '{1440}'::int[]
    when '1d2h' then '{1440,120}'::int[]
    else '{}'::int[]
  end);
end;
$$;
revoke execute on function set_calendar_reminders(text) from public;
grant execute on function set_calendar_reminders(text) to authenticated;
