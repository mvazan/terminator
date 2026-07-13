-- Multitenancy, part 1: the teams table, team_id on root tables, helpers and
-- reworked membership RPCs. BREAKING for pre-2.0 clients (team_settings is
-- dropped) — deploy together with 0013 and the 2.0.0 app release.
--
-- Design: team_id lives only on the ROOT tables (profiles, venues,
-- tournaments, team_messages); leaf tables (slots, orders, availability,
-- rosters, messages, …) derive their team through FK chains via SECURITY
-- DEFINER helpers (0013). A BEFORE INSERT trigger stamps team_id from the
-- inserting user's profile, so clients never send it.

-- ---------------------------------------------------------------------------
-- Teams
-- ---------------------------------------------------------------------------

create table teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (name <> ''),
  invite_code text not null,
  manage_pin text not null,
  -- New teams wait for the superadmin's one-time approval before their
  -- members can use the app (mirrors member approval, one level up).
  status text not null default 'pending'
    check (status in ('pending', 'approved')),
  -- The founder — sees the manage-PIN explainer in settings.
  created_by uuid references profiles (id) on delete set null,
  approved_by uuid references profiles (id),
  approved_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index teams_invite_code_idx on teams (lower(invite_code));

-- Seed the existing team from the LIVE team_settings row (never literals —
-- the code/PIN may have been changed in production). Approved from day one.
insert into teams (name, invite_code, manage_pin, status, approved_at)
select 'Veverky', invite_code, manage_pin, 'approved', now()
from team_settings;

grant select on teams to authenticated;
grant all on teams to service_role;

-- ---------------------------------------------------------------------------
-- team_id on root tables + superadmin flag, backfilled to the seeded team
-- ---------------------------------------------------------------------------

alter table profiles      add column team_id uuid references teams (id);
alter table venues        add column team_id uuid references teams (id);
alter table tournaments   add column team_id uuid references teams (id);
alter table team_messages add column team_id uuid references teams (id);
alter table profiles      add column superadmin boolean not null default false;

do $$
declare v_team uuid;
begin
  select id into v_team from teams where lower(invite_code) = lower(
    (select invite_code from team_settings limit 1));
  update profiles      set team_id = v_team;
  update venues        set team_id = v_team;
  update tournaments   set team_id = v_team;
  update team_messages set team_id = v_team;
end $$;

alter table profiles      alter column team_id set not null;
alter table venues        alter column team_id set not null;
alter table tournaments   alter column team_id set not null;
alter table team_messages alter column team_id set not null;

create index profiles_team_idx      on profiles (team_id);
create index venues_team_idx        on venues (team_id);
create index tournaments_team_idx   on tournaments (team_id);
create index team_messages_team_idx on team_messages (team_id);

-- The app owner approves new teams. Identified by login e-mail.
update profiles set superadmin = true
where id = (select id from auth.users where email = 'milos.vazan@gmail.com');

-- The migrated team's founder = the app owner.
update teams set created_by =
  (select id from auth.users where email = 'milos.vazan@gmail.com');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function my_team()
returns uuid
language sql stable security definer set search_path = public
as $$
  select team_id from profiles where id = auth.uid();
$$;

create or replace function is_superadmin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select superadmin from profiles where id = auth.uid()), false);
$$;

-- Clients insert without team_id; stamp it from the inserter's profile.
-- RLS WITH CHECK evaluates the row AFTER before-triggers, so stamped rows
-- pass the team policies in 0013.
create or replace function set_team_id()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.team_id is null then
    new.team_id := my_team();
  end if;
  return new;
end;
$$;

create trigger venues_set_team
  before insert on venues for each row execute function set_team_id();
create trigger tournaments_set_team
  before insert on tournaments for each row execute function set_team_id();
create trigger team_messages_set_team
  before insert on team_messages for each row execute function set_team_id();

-- ---------------------------------------------------------------------------
-- join_team reworked: invite code resolves a TEAM; first member OF THAT TEAM
-- is auto-approved. (No trigger on profiles — the RPCs set team_id.)
-- ---------------------------------------------------------------------------

create or replace function join_team(p_invite_code text, p_display_name text)
returns profiles
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team uuid;
  v_profile profiles;
  v_first boolean;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_profile from profiles where id = v_uid;
  if found then return v_profile; end if;

  select id into v_team from teams
  where lower(trim(invite_code)) = lower(trim(p_invite_code));
  if v_team is null then raise exception 'invalid_invite_code'; end if;

  if trim(p_display_name) = '' then raise exception 'empty_display_name'; end if;

  select not exists (
    select 1 from profiles where team_id = v_team and status = 'approved'
  ) into v_first;

  insert into profiles (id, display_name, team_id, status, approved_at)
  values (v_uid, trim(p_display_name), v_team,
          case when v_first then 'approved' else 'pending' end,
          case when v_first then now() end)
  returning * into v_profile;

  return v_profile;
end;
$$;

-- ---------------------------------------------------------------------------
-- team_settings is gone: the app (2.0.0+) reads its own team from `teams`.
-- ---------------------------------------------------------------------------

drop policy team_settings_select on team_settings;
drop table team_settings;

-- ---------------------------------------------------------------------------
-- Teams RLS + realtime (members see their own team; superadmin sees all —
-- needed for the approval UI).
-- ---------------------------------------------------------------------------

alter table teams enable row level security;

create policy teams_select on teams for select
  using (id = my_team() or is_superadmin());

alter publication supabase_realtime add table teams;
