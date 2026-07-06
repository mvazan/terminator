-- Termínátor — initial schema
-- One team space. Access model: magic-link auth + invite code + member approval.
-- All approved members are equal (no admin role).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- Private team configuration. No RLS policies are created for it on purpose:
-- clients can never read it; only security-definer functions touch it.
create table team_settings (
  id boolean primary key default true check (id),
  invite_code text not null
);

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  phone text,
  fcm_token text,
  status text not null default 'pending' check (status in ('pending', 'approved')),
  approved_by uuid references profiles (id),
  approved_at timestamptz,
  created_at timestamptz not null default now()
);

create table tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  venue text not null default '',
  kind text not null default '',
  starts_on date not null,
  ends_on date not null check (ends_on >= starts_on),
  min_players int not null default 2 check (min_players > 0),
  max_players int check (max_players is null or max_players >= min_players),
  ordering_contact text not null default '',
  notes text not null default '',
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);

create table slots (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments (id) on delete cascade,
  date date not null,
  time time not null,
  -- set by the notify function when the min-players push was sent (dedup)
  threshold_notified_at timestamptz,
  unique (tournament_id, date, time)
);
create index slots_tournament_date_idx on slots (tournament_id, date);

create table availability (
  slot_id uuid not null references slots (id) on delete cascade,
  user_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (slot_id, user_id)
);
create index availability_user_idx on availability (user_id);

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

-- One row per filled place of an ordered slot. Either a member or a free-text
-- guest (someone without the app). Places may stay empty; capacity is
-- tournaments.max_players per slot.
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

-- ---------------------------------------------------------------------------
-- Helper + RPC functions
-- ---------------------------------------------------------------------------

-- True when the caller has an approved profile. SECURITY DEFINER so policies
-- on other tables can use it without recursive RLS lookups on profiles.
create or replace function is_approved()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from profiles where id = auth.uid() and status = 'approved'
  );
$$;

-- Called once after the first magic-link sign-in. Validates the invite code
-- and creates the caller's profile. The very first member (no approved
-- profiles yet) is auto-approved — the founder.
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

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table team_settings enable row level security;  -- no policies: locked
alter table profiles      enable row level security;
alter table tournaments   enable row level security;
alter table slots         enable row level security;
alter table availability  enable row level security;
alter table orders        enable row level security;
alter table order_slots   enable row level security;
alter table order_votes   enable row level security;
alter table rosters       enable row level security;
alter table messages      enable row level security;
alter table chat_mutes    enable row level security;

-- profiles: everyone sees their own row (needed while pending); approved
-- members see the whole team. Members edit only their own name/phone/token —
-- column-level grants keep status/approved_* out of reach (approval goes
-- through the approve_member() function only).
revoke update on profiles from authenticated;
grant update (display_name, phone, fcm_token) on profiles to authenticated;

create policy profiles_select on profiles for select
  using (id = auth.uid() or is_approved());
create policy profiles_update_own on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- Team data: full access for approved members (trusted, everyone equal),
-- with ownership checks where a row speaks for a person.
create policy tournaments_all on tournaments for all
  using (is_approved()) with check (is_approved());

create policy slots_all on slots for all
  using (is_approved()) with check (is_approved());

create policy availability_select on availability for select
  using (is_approved());
create policy availability_insert on availability for insert
  with check (is_approved() and user_id = auth.uid());
create policy availability_delete on availability for delete
  using (user_id = auth.uid());

create policy orders_all on orders for all
  using (is_approved()) with check (is_approved());

create policy order_slots_all on order_slots for all
  using (is_approved()) with check (is_approved());

create policy order_votes_select on order_votes for select
  using (is_approved());
create policy order_votes_insert on order_votes for insert
  with check (is_approved() and user_id = auth.uid());
create policy order_votes_update on order_votes for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy order_votes_delete on order_votes for delete
  using (user_id = auth.uid());

create policy rosters_all on rosters for all
  using (is_approved()) with check (is_approved() and added_by = auth.uid());

create policy messages_select on messages for select
  using (is_approved());
create policy messages_insert on messages for insert
  with check (is_approved() and user_id = auth.uid());
create policy messages_delete_own on messages for delete
  using (user_id = auth.uid());

create policy chat_mutes_own on chat_mutes for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table
  profiles, tournaments, slots, availability,
  orders, order_slots, order_votes, rosters, messages;
