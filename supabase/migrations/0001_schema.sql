-- Termínátor — canonical schema (single clean baseline).
-- One team space. Access model: magic-link auth + invite code + member
-- approval. All approved members are equal (no admin role). Archived
-- tournaments are read-only, enforced here in RLS, not just in the UI.
--
-- This is a squash of the original 0001 + eight incremental migrations, done
-- while the DB was empty. History dropped on purpose; columns are declared
-- inline and intermediate churn (added-then-dropped policies/columns) is gone.

create extension if not exists pgcrypto;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- Tables  (order matters: FKs must reference already-created tables)
-- ---------------------------------------------------------------------------

-- Private team configuration. No RLS write policy: clients never write it.
-- Approved members may read it (needed for the manage-mode PIN).
create table team_settings (
  id boolean primary key default true check (id),
  invite_code text not null,
  -- Shared PIN gating the hidden "manage" mode (unlock gesture + this PIN).
  -- Not a security boundary — decluttering only. Seeded below.
  manage_pin text not null
);

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  fcm_token text,
  status text not null default 'pending' check (status in ('pending', 'approved')),
  approved_by uuid references profiles (id),
  approved_at timestamptz,
  -- soft-hide from the everyday UI (reversible; via set_member_hidden())
  hidden_at timestamptz,
  created_at timestamptz not null default now()
);

-- Bowling alleys, reused across tournaments so the lane count + address are
-- entered once. Only lane_count is required. Organizer contacts live on the
-- tournament (one venue may host several clubs), so only the home-club
-- website lives here.
create table venues (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  lane_count int not null check (lane_count > 0),
  address text not null default '',
  source_url text not null default '',
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now()
);

-- kind values mirror TournamentKind in lib/domain/models.dart; per-start
-- player capacity is derived from kind in the app. discipline is a second,
-- optional axis (throw format). The venue name is read via venue_id (no
-- denormalized free-text copy).
create table tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  venue_id uuid not null references venues (id),
  kind text not null default 'dvojice'
    check (kind in ('jednotlivci', 'dvojice', 'čtveřice', 'tandem')),
  discipline text
    check (discipline in ('60HS', '100HS', '120HS', '180HS', 'jiné')),
  starts_on date not null,
  ends_on date not null check (ends_on >= starts_on),
  min_players int not null default 2 check (min_players > 0),
  contact_email text not null default '',
  contact_phone text not null default '',
  source_url text not null default '',
  scraped_at timestamptz,
  notes text not null default '',
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  archived_at timestamptz,
  -- soft-hide the tournament (and, in the UI, its chats/orders)
  hidden_at timestamptz,
  -- per-tournament cooldown state for grouped "dá se objednat" pushes,
  -- flipped atomically by the notify function
  threshold_notified_at timestamptz
);
create index tournaments_venue_idx on tournaments (venue_id);

create table slots (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments (id) on delete cascade,
  date date not null,
  time time not null,
  -- venue occupancy from web scraping (null = manual slot, no info)
  venue_capacity int,
  venue_occupied int,
  -- per-slot dedup: set once when this slot first crossed min_players, so a
  -- slot never notifies twice (distinct from the per-tournament cooldown above)
  threshold_notified_at timestamptz,
  -- also serves lookups by (tournament_id, date); used by scrape upserts
  unique (tournament_id, date, time)
);

create table availability (
  slot_id uuid not null references slots (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (slot_id, user_id)
);

create table orders (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments (id) on delete cascade,
  created_by uuid not null references profiles (id),
  -- a proposal is simply an order in 'proposed' state
  status text not null default 'proposed'
    check (status in ('proposed', 'ordered', 'confirmed', 'cancelled')),
  note text not null default '',
  created_at timestamptz not null default now(),
  ordered_at timestamptz
);
create index orders_tournament_idx on orders (tournament_id);

create table order_slots (
  order_id uuid not null references orders (id) on delete cascade,
  slot_id uuid not null references slots (id) on delete cascade,
  -- lanes ordered for this start. Player capacity = lanes × players-per-lane
  -- (tandem = 2 per lane, everything else 1), computed in the app.
  lanes int not null default 1 check (lanes > 0),
  primary key (order_id, slot_id)
);
create index order_slots_slot_idx on order_slots (slot_id);

create table order_votes (
  order_id uuid not null references orders (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  vote text not null check (vote in ('in', 'out', 'other_day')),
  note text not null default '',
  created_at timestamptz not null default now(),
  primary key (order_id, user_id)
);

-- One row per filled place of an ordered slot: a member or a free-text guest.
-- Places may stay empty; capacity per slot is derived from tournaments.kind.
create table rosters (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references slots (id) on delete cascade,
  user_id uuid references profiles (id) on delete cascade,
  guest_name text,
  added_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  check (user_id is not null or (guest_name is not null and guest_name <> ''))
);
create unique index rosters_slot_user_idx on rosters (slot_id, user_id)
  where user_id is not null;
create index rosters_slot_idx on rosters (slot_id);

-- day = null  -> tournament chat (all members, exists for every tournament)
-- day set     -> day chat for a played day (participants = that day's rosters)
create table messages (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments (id) on delete cascade,
  day date,
  user_id uuid not null references profiles (id),
  body text not null check (body <> ''),
  created_at timestamptz not null default now()
);
create index messages_chat_idx on messages (tournament_id, day, created_at);

create table chat_mutes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  tournament_id uuid not null references tournaments (id) on delete cascade,
  day date,
  created_at timestamptz not null default now()
);
create unique index chat_mutes_unique_idx
  on chat_mutes (user_id, tournament_id, coalesce(day, '0001-01-01'::date));

-- Per-user, per-kind notification preferences. Missing row = the kind's
-- default. The kind list lives in THREE places that must stay in sync: this
-- CHECK constraint, NotificationKind in lib/domain/models.dart, and
-- NotificationKind + DEFAULT_OFF in supabase/functions/notify/index.ts.
create table notification_prefs (
  user_id uuid not null references profiles (id) on delete cascade,
  kind text not null check (kind in (
    'new_member', 'new_tournament', 'proposal', 'order', 'chat', 'threshold'
  )),
  enabled boolean not null default true,
  muted_until timestamptz,
  primary key (user_id, kind)
);

-- ---------------------------------------------------------------------------
-- Functions
-- ---------------------------------------------------------------------------

create or replace function is_approved()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from profiles where id = auth.uid() and status = 'approved'
  );
$$;

create or replace function is_tournament_archived(p_tournament_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select archived_at is not null from tournaments where id = p_tournament_id;
$$;

-- First sign-in: validate the invite code and create the caller's profile.
-- The very first member (no approved profiles yet) is auto-approved.
create or replace function join_team(p_invite_code text, p_display_name text)
returns profiles
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
  v_first boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_profile from profiles where id = v_uid;
  if found then
    return v_profile;
  end if;

  if not exists (
    select 1 from team_settings
    where lower(trim(invite_code)) = lower(trim(p_invite_code))
  ) then
    raise exception 'invalid_invite_code';
  end if;

  if trim(p_display_name) = '' then
    raise exception 'empty_display_name';
  end if;

  select not exists (select 1 from profiles where status = 'approved')
    into v_first;

  insert into profiles (id, display_name, status, approved_at)
  values (
    v_uid,
    trim(p_display_name),
    case when v_first then 'approved' else 'pending' end,
    case when v_first then now() end
  )
  returning * into v_profile;

  return v_profile;
end;
$$;

-- Any approved member can approve a pending member (everyone equal).
create or replace function approve_member(p_user_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_approved() then
    raise exception 'not_approved';
  end if;

  update profiles
  set status = 'approved', approved_by = auth.uid(), approved_at = now()
  where id = p_user_id and status = 'pending';
end;
$$;

-- Soft-hide (status -> pending, so re-showing needs re-approval) or un-hide a
-- member. SECURITY DEFINER so members can hide others without a broad grant on
-- the profiles table. Approved members only.
create or replace function set_member_hidden(p_user_id uuid, p_hidden boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_approved() then
    raise exception 'not_approved';
  end if;

  if p_hidden then
    update profiles
    set hidden_at = now(), status = 'pending', approved_by = null,
        approved_at = null
    where id = p_user_id;
  else
    update profiles set hidden_at = null where id = p_user_id;
  end if;
end;
$$;

-- Webhook fan-out: every event the notify Edge Function cares about is
-- delivered by a pg_net POST from the triggers below. The x-webhook-secret
-- header must match the WEBHOOK_SECRET secret.
-- NOTE: the project URL is hardcoded — if the project ref ever changes (region
-- move), update it here AND redeploy. (This bit us once: after the Ireland →
-- Frankfurt move the old URL lingered and silently dropped every push.)
create or replace function notify_webhook()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://txieiufeccpnnceunyxo.supabase.co/functions/v1/notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '3f3681ba6f2a83b0e2c0ad6f3619d27bb856d3ba8dd44ee4'
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', case when tg_op = 'DELETE' then null else to_jsonb(new) end,
      'old_record', case when tg_op = 'INSERT' then null else to_jsonb(old) end
    )
  );
  return coalesce(new, old);
end;
$$;

create trigger notify_profiles
  after insert on profiles
  for each row execute function notify_webhook();
create trigger notify_tournaments
  after insert on tournaments
  for each row execute function notify_webhook();
create trigger notify_orders
  after insert or update on orders
  for each row execute function notify_webhook();
create trigger notify_messages
  after insert on messages
  for each row execute function notify_webhook();
create trigger notify_availability
  after insert on availability
  for each row execute function notify_webhook();

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
-- PostgREST checks table-level privileges BEFORE RLS, so the authenticated
-- role needs CRUD grants on every table (RLS then restricts which rows).
-- Supabase normally sets these as schema defaults, but `drop schema public`
-- during the squash wiped them — re-grant them here so a clean rebuild works.
-- The profiles column-grant tightening below narrows UPDATE afterwards.
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to authenticated, service_role;
grant all on all sequences in schema public to authenticated, service_role;
grant all on all functions in schema public to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table team_settings      enable row level security;
alter table profiles           enable row level security;
alter table venues             enable row level security;
alter table tournaments        enable row level security;
alter table slots              enable row level security;
alter table availability       enable row level security;
alter table orders             enable row level security;
alter table order_slots        enable row level security;
alter table order_votes        enable row level security;
alter table rosters            enable row level security;
alter table messages           enable row level security;
alter table chat_mutes         enable row level security;
alter table notification_prefs enable row level security;

-- team_settings: read-only for approved members (manage-mode PIN); no write.
create policy team_settings_select on team_settings for select
  using (is_approved());

-- profiles: everyone sees their own row (needed while pending); approved
-- members see the whole team. Members edit only their own name/token —
-- column-level grants keep status/approved_*/hidden_at out of reach (approval
-- via approve_member(), hiding via set_member_hidden(), both SECURITY DEFINER).
revoke update on profiles from authenticated;
grant update (display_name, fcm_token) on profiles to authenticated;

create policy profiles_select on profiles for select
  using (id = auth.uid() or is_approved());
create policy profiles_update_own on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- venues: approved members can read, add, edit. No delete (referenced by
-- tournaments).
create policy venues_select on venues for select
  using (is_approved());
create policy venues_insert on venues for insert
  with check (is_approved());
create policy venues_update on venues for update
  using (is_approved()) with check (is_approved());

-- tournaments: full access for approved members; archiving itself stays
-- possible (and reversible) via update.
create policy tournaments_select on tournaments for select
  using (is_approved());
create policy tournaments_insert on tournaments for insert
  with check (is_approved());
create policy tournaments_update on tournaments for update
  using (is_approved()) with check (is_approved());
create policy tournaments_delete on tournaments for delete
  using (is_approved() and archived_at is null);

-- Team data below: writes are blocked once the tournament is archived.
create policy slots_select on slots for select
  using (is_approved());
create policy slots_insert on slots for insert
  with check (is_approved() and not is_tournament_archived(tournament_id));
create policy slots_update on slots for update
  using (is_approved() and not is_tournament_archived(tournament_id))
  with check (is_approved() and not is_tournament_archived(tournament_id));
create policy slots_delete on slots for delete
  using (is_approved() and not is_tournament_archived(tournament_id));

create policy availability_select on availability for select
  using (is_approved());
create policy availability_insert on availability for insert
  with check (
    is_approved() and user_id = auth.uid()
    and not is_tournament_archived(
      (select tournament_id from slots where id = slot_id)
    )
  );
create policy availability_delete on availability for delete
  using (user_id = auth.uid());

create policy orders_select on orders for select
  using (is_approved());
create policy orders_insert on orders for insert
  with check (is_approved() and not is_tournament_archived(tournament_id));
create policy orders_update on orders for update
  using (is_approved() and not is_tournament_archived(tournament_id))
  with check (is_approved() and not is_tournament_archived(tournament_id));
create policy orders_delete on orders for delete
  using (is_approved() and not is_tournament_archived(tournament_id));

create policy order_slots_select on order_slots for select
  using (is_approved());
create policy order_slots_insert on order_slots for insert
  with check (
    is_approved()
    and not is_tournament_archived(
      (select tournament_id from orders where id = order_id)
    )
  );
create policy order_slots_delete on order_slots for delete
  using (is_approved());

create policy order_votes_select on order_votes for select
  using (is_approved());
create policy order_votes_insert on order_votes for insert
  with check (
    is_approved() and user_id = auth.uid()
    and not is_tournament_archived(
      (select tournament_id from orders where id = order_id)
    )
  );
create policy order_votes_update on order_votes for update
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and not is_tournament_archived(
      (select tournament_id from orders where id = order_id)
    )
  );
create policy order_votes_delete on order_votes for delete
  using (user_id = auth.uid());

create policy rosters_select on rosters for select
  using (is_approved());
create policy rosters_insert on rosters for insert
  with check (
    is_approved() and added_by = auth.uid()
    and not is_tournament_archived(
      (select tournament_id from slots where id = slot_id)
    )
  );
create policy rosters_delete on rosters for delete
  using (is_approved());

create policy messages_select on messages for select
  using (is_approved());
create policy messages_insert on messages for insert
  with check (is_approved() and user_id = auth.uid());
create policy messages_delete_own on messages for delete
  using (user_id = auth.uid());

create policy chat_mutes_own on chat_mutes for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy notification_prefs_own on notification_prefs for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table
  profiles, venues, tournaments, slots, availability,
  orders, order_slots, order_votes, rosters, messages,
  chat_mutes, notification_prefs;

-- ---------------------------------------------------------------------------
-- Seed  (idempotent; won't clobber a changed code/PIN on re-run)
-- ---------------------------------------------------------------------------

insert into team_settings (id, invite_code, manage_pin)
select true, 'veverky', '2468'
where not exists (select 1 from team_settings);
