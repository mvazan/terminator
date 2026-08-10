-- Google Calendar: starty hráče se samy objevují (a mizí) v jeho Google
-- kalendáři. Appka si v jeho účtu založí VLASTNÍ sekundární kalendář
-- „Termínátor" (scope calendar.app.created — na ostatní kalendáře nevidí)
-- a spravuje výhradně ten.
--
-- Sync jede na enginu notification_jobs (0025), cestou č. 2 (odložené joby) —
-- žádná třetí cesta, viz NOTIFICATIONS.md. Jediný druh jobu `calendar_sync`
-- je RECONCILE: handler si při běhu ověří realitu (jsi pořád v rosteru
-- aktivní objednávky?) a podle toho event ZALOŽÍ, nebo SMAŽE. Proto:
--   * netřeba dvojice kindů upsert/delete (a tím pádem ani `kind` v
--     ON CONFLICT u enqueue_notification, který ho záměrně nepřepisuje);
--   * undo pravidlo netřeba — přidání a hned odebrání se debounce-uje do
--     JEDNOHO jobu, který udělá správnou věc (nic, nebo smazání).
-- Klíč `calendar:<user>:<slot>` je tedy stejný pro obě strany.
--
-- Kalendářové joby se enqueují NEZÁVISLE na notification_prefs a i při
-- self-addu: sync není notifikace a vlastní start do kalendáře patří.

-- ---------------------------------------------------------------------------
-- Stav propojení (čte klient) vs. tokeny (nikdy neopustí server)
-- ---------------------------------------------------------------------------

-- Klientem viditelný stav — ŽÁDNÁ tajemství. Realtime stream téhle tabulky
-- překlopí dlaždici v nastavení, jakmile callback EF dopíše výsledek.
create table google_calendar_links (
  user_id uuid primary key references profiles (id) on delete cascade,
  -- pending = token uložen, kalendář se ještě nezaložil; broken = uživatel
  -- odvolal přístup nebo kalendář smazal → v nastavení nabídneme re-link.
  status text not null default 'pending'
    check (status in ('pending', 'linked', 'broken')),
  google_email text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table google_calendar_links enable row level security;
grant all on google_calendar_links to service_role;
-- Vlastní řádek smí člověk číst (vzor profiles_select), psát jen server.
-- Teammates si navzájem do propojení nevidí — na rozdíl od profiles není
-- důvod, aby kdokoli znal cizí Google e-mail.
grant select on google_calendar_links to authenticated;
revoke insert, update, delete on google_calendar_links from authenticated;
create policy google_calendar_links_select_own on google_calendar_links
  for select using (user_id = auth.uid());

-- Refresh token a id založeného kalendáře. Server-only tabulka: RLS on, žádné
-- policy (vzor notification_jobs). Schválně SAMOSTATNÁ tabulka — stav výše se
-- streamuje klientovi přes Realtime a token nesmí být ani v tabulce, kterou
-- klient streamuje (column-level granty Realtime nefiltruje spolehlivě).
create table google_calendar_tokens (
  user_id uuid primary key references profiles (id) on delete cascade,
  refresh_token text not null,
  google_calendar_id text,
  updated_at timestamptz not null default now()
);
alter table google_calendar_tokens enable row level security;
grant all on google_calendar_tokens to service_role;

alter publication supabase_realtime add table google_calendar_links;

-- ---------------------------------------------------------------------------
-- OAuth `state` nonce: CSRF + vazba návratu z Googlu na konkrétního uživatele
-- ---------------------------------------------------------------------------

-- Callback EF běží s --no-verify-jwt (Google JWT poslat neumí), takže důvěru
-- nese tenhle nonce: neuhodnutelný, jednorázový, s TTL 10 minut a vydaný
-- výhradně přihlášenému schválenému členovi.
create table oauth_nonces (
  nonce text primary key default encode(gen_random_bytes(24), 'hex'),
  user_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  consumed_at timestamptz
);
alter table oauth_nonces enable row level security;
grant all on oauth_nonces to service_role;

create or replace function start_calendar_link()
returns text
language plpgsql security definer set search_path = public
as $$
declare
  v_nonce text;
begin
  if not is_approved() then
    raise exception 'not_approved';
  end if;
  -- Kdo souhlas v Googlu zavře a zkusí to znovu, nemá si hromadit řádky.
  delete from oauth_nonces
    where user_id = auth.uid() and consumed_at is null;
  insert into oauth_nonces (user_id) values (auth.uid())
    returning nonce into v_nonce;
  return v_nonce;
end;
$$;
revoke execute on function start_calendar_link() from public;
grant execute on function start_calendar_link() to authenticated;

/** Spotřebuje nonce a vrátí uživatele, na kterého byl vázán. NULL = neplatný,
 * už použitý, nebo starší než 10 minut. Volá jen callback EF (service_role). */
create or replace function consume_calendar_nonce(p_nonce text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid;
begin
  update oauth_nonces
    set consumed_at = now()
    where nonce = p_nonce
      and consumed_at is null
      and created_at > now() - interval '10 minutes'
    returning user_id into v_user;
  return v_user;
end;
$$;
revoke execute on function consume_calendar_nonce(text) from public;
grant execute on function consume_calendar_nonce(text) to service_role;

-- Odpojení: token odvoláme u Googlu (pg_net, stejně jako notify_webhook)
-- a zapomeneme obě strany. Kalendář v Googlu ZÁMĚRNĚ nemažeme — „odpojit
-- appku" neznamená „smazat mi data", to je konvence i u samotného Googlu.
create or replace function disconnect_calendar()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_token text;
begin
  select refresh_token into v_token
    from google_calendar_tokens where user_id = auth.uid();
  if v_token is not null then
    -- Token jde v query parametru: pg_net posílá jen JSON tělo a trvá na
    -- Content-Type: application/json, kdežto revoke endpoint čeká form —
    -- query parametr přijímají obě strany. Odpověď nás nezajímá: když revoke
    -- selže, token stejně zahazujeme a přístup jde odebrat i v nastavení
    -- Google účtu.
    perform net.http_post(
      url := 'https://oauth2.googleapis.com/revoke',
      params := jsonb_build_object('token', v_token)
    );
  end if;
  delete from google_calendar_tokens where user_id = auth.uid();
  delete from google_calendar_links where user_id = auth.uid();
end;
$$;
revoke execute on function disconnect_calendar() from public;
grant execute on function disconnect_calendar() to authenticated;

-- ---------------------------------------------------------------------------
-- Producenti jobů
-- ---------------------------------------------------------------------------

-- Retry pro kalendářové joby: na rozdíl od pushů se výpadek Google API vyplatí
-- zkusit znovu (push kindy si job po pokusu pořád mažou — viz processJobs).
alter table notification_jobs add column attempts int not null default 0;

/** Enqueue kalendářového sync jobu pro (uživatel, slot). Hosté (bez user_id)
 * nemají kam synchronizovat. Volá se z obou triggerů níž. */
create or replace function enqueue_calendar_sync(p_user uuid, p_slot uuid)
returns void
language sql security definer set search_path = public
as $$
  select enqueue_notification('calendar_sync',
    'calendar:' || p_user || ':' || p_slot,
    jsonb_build_object('user_id', p_user, 'slot_id', p_slot))
  where p_user is not null and p_slot is not null;
$$;

-- Stejné tělo jako 0025, jen s kalendářovou větví na začátku (vzor 0012).
-- Kalendářová větev musí být PŘED notifikační logikou: ta má pro self-add
-- a undo brzké returny, které pro kalendář neplatí.
create or replace function rosters_enqueue_jobs()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := coalesce(new.user_id, old.user_id);
  v_slot uuid := coalesce(new.slot_id, old.slot_id);
  v_order uuid;
begin
  select o.id into v_order
    from order_slots os
    join orders o on o.id = os.order_id
    where os.slot_id = v_slot
      and o.status in ('ordered', 'confirmed')
    limit 1;
  if v_order is null then
    return coalesce(new, old);
  end if;

  -- Kalendář: reaguje na KAŽDOU změnu rosteru včetně self-addu; jeden druh
  -- jobu pro insert i delete, handler si realitu ověří sám.
  perform enqueue_calendar_sync(v_user, v_slot);

  if tg_op = 'INSERT' then
    -- Guests have no device; self-joins need no notice.
    if v_user is null or v_user = auth.uid() then return new; end if;
    -- Removed a moment ago and now back: net zero, tell them nothing.
    if dequeue_notification('removed:' || v_user || ':' || v_order) then
      return new;
    end if;
    perform enqueue_notification('assigned',
      'assigned:' || v_user || ':' || v_order,
      jsonb_build_object('order_id', v_order, 'user_id', v_user,
                         'added_by', new.added_by));
    return new;
  end if;

  -- DELETE: a place may have opened up — re-run the digest.
  perform enqueue_notification('order_free_spots',
    'order_free_spots:' || v_order,
    jsonb_build_object('order_id', v_order));
  if v_user is null or v_user = auth.uid() then return old; end if;
  -- Added a moment ago and now removed: they never knew — no ping-pong.
  if dequeue_notification('assigned:' || v_user || ':' || v_order) then
    return old;
  end if;
  perform enqueue_notification('removed',
    'removed:' || v_user || ':' || v_order,
    jsonb_build_object('order_id', v_order, 'user_id', v_user));
  return old;
end;
$$;

-- Stejné tělo jako 0025 + zrušení objednávky smaže starty z kalendářů všech,
-- kdo v ní byli rostrovaní (rosters řádky zrušení nemaže, takže je pořád
-- vidíme — stejný dotaz dělá i push „Zrušeno" v notify EF).
create or replace function orders_enqueue_jobs()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_roster record;
begin
  if new.status = 'ordered' and
     (tg_op = 'INSERT' or old.status is distinct from new.status) then
    perform enqueue_notification('order_free_spots',
      'order_free_spots:' || new.id,
      jsonb_build_object('order_id', new.id));
  end if;

  if tg_op = 'UPDATE' and new.status = 'cancelled'
     and old.status is distinct from 'cancelled' then
    for v_roster in
      select r.user_id, r.slot_id
        from order_slots os
        join rosters r on r.slot_id = os.slot_id
        where os.order_id = new.id and r.user_id is not null
    loop
      perform enqueue_calendar_sync(v_roster.user_id, v_roster.slot_id);
    end loop;
  end if;

  return new;
end;
$$;

/** Po propojení účtu: naplánuj sync všech budoucích startů uživatele.
 * run_at = now() (ne obvyklé 3 minuty) — tohle je jednorázová akce, ne
 * reakce na uklik. Volá callback EF přes service_role. */
create or replace function backfill_calendar_jobs(p_user_id uuid)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_count int := 0;
begin
  with future_starts as (
    select distinct r.slot_id
      from rosters r
      join slots s on s.id = r.slot_id
      join order_slots os on os.slot_id = r.slot_id
      join orders o on o.id = os.order_id
      where r.user_id = p_user_id
        and o.status in ('ordered', 'confirmed')
        and s.date >= current_date
  )
  insert into notification_jobs (kind, dedupe_key, payload, run_at)
  select 'calendar_sync',
         'calendar:' || p_user_id || ':' || slot_id,
         jsonb_build_object('user_id', p_user_id, 'slot_id', slot_id),
         now()
    from future_starts
  on conflict (dedupe_key) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function backfill_calendar_jobs(uuid) from public;
grant execute on function backfill_calendar_jobs(uuid) to service_role;
