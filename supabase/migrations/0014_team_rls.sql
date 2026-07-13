-- Multitenancy, part 2: team-scoped RLS everywhere, team-scoped RPCs, and
-- team creation/approval. Deploys together with 0012 + the 2.0.0 release.

-- ---------------------------------------------------------------------------
-- The gate: approved member of an APPROVED team. One body change re-scopes
-- every policy that calls is_approved(); pending-team members see nothing.
-- ---------------------------------------------------------------------------

create or replace function is_approved()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from profiles p join teams t on t.id = p.team_id
    where p.id = auth.uid() and p.status = 'approved'
      and t.status = 'approved'
  );
$$;

-- Leaf scoping helpers — same SECURITY DEFINER pattern as
-- is_tournament_archived (0001).
create or replace function is_my_tournament(p_tournament_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from tournaments
                 where id = p_tournament_id and team_id = my_team());
$$;

create or replace function is_my_slot(p_slot_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from slots s
                 join tournaments t on t.id = s.tournament_id
                 where s.id = p_slot_id and t.team_id = my_team());
$$;

create or replace function is_my_order(p_order_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from orders o
                 join tournaments t on t.id = o.tournament_id
                 where o.id = p_order_id and t.team_id = my_team());
$$;

-- ---------------------------------------------------------------------------
-- Policy rewrites. Group A: root tables gain `team_id = my_team()`.
-- ---------------------------------------------------------------------------

drop policy profiles_select on profiles;
create policy profiles_select on profiles for select
  using (id = auth.uid() or (is_approved() and team_id = my_team()));

drop policy venues_select on venues;
create policy venues_select on venues for select
  using (is_approved() and team_id = my_team());
drop policy venues_insert on venues;
create policy venues_insert on venues for insert
  with check (is_approved() and team_id = my_team());
drop policy venues_update on venues;
create policy venues_update on venues for update
  using (is_approved() and team_id = my_team())
  with check (is_approved() and team_id = my_team());

drop policy tournaments_select on tournaments;
create policy tournaments_select on tournaments for select
  using (is_approved() and team_id = my_team());
drop policy tournaments_insert on tournaments;
create policy tournaments_insert on tournaments for insert
  with check (is_approved() and team_id = my_team());
drop policy tournaments_update on tournaments;
create policy tournaments_update on tournaments for update
  using (is_approved() and team_id = my_team())
  with check (is_approved() and team_id = my_team());
drop policy tournaments_delete on tournaments;
create policy tournaments_delete on tournaments for delete
  using (is_approved() and team_id = my_team() and archived_at is null);

drop policy team_messages_select on team_messages;
create policy team_messages_select on team_messages for select
  using (is_approved() and team_id = my_team());
drop policy team_messages_insert on team_messages;
create policy team_messages_insert on team_messages for insert
  with check (user_id = auth.uid() and is_approved()
              and team_id = my_team());

-- ---------------------------------------------------------------------------
-- Group B: leaves keyed by tournament_id.
-- ---------------------------------------------------------------------------

drop policy slots_select on slots;
create policy slots_select on slots for select
  using (is_approved() and is_my_tournament(tournament_id));
drop policy slots_insert on slots;
create policy slots_insert on slots for insert
  with check (is_approved() and is_my_tournament(tournament_id)
              and not is_tournament_archived(tournament_id));
drop policy slots_update on slots;
create policy slots_update on slots for update
  using (is_approved() and is_my_tournament(tournament_id)
         and not is_tournament_archived(tournament_id))
  with check (is_approved() and is_my_tournament(tournament_id)
              and not is_tournament_archived(tournament_id));
drop policy slots_delete on slots;
create policy slots_delete on slots for delete
  using (is_approved() and is_my_tournament(tournament_id)
         and not is_tournament_archived(tournament_id));

drop policy orders_select on orders;
create policy orders_select on orders for select
  using (is_approved() and is_my_tournament(tournament_id));
drop policy orders_insert on orders;
create policy orders_insert on orders for insert
  with check (is_approved() and is_my_tournament(tournament_id)
              and not is_tournament_archived(tournament_id));
drop policy orders_update on orders;
create policy orders_update on orders for update
  using (is_approved() and is_my_tournament(tournament_id)
         and not is_tournament_archived(tournament_id))
  with check (is_approved() and is_my_tournament(tournament_id)
              and not is_tournament_archived(tournament_id));
drop policy orders_delete on orders;
create policy orders_delete on orders for delete
  using (is_approved() and is_my_tournament(tournament_id)
         and not is_tournament_archived(tournament_id));

drop policy messages_select on messages;
create policy messages_select on messages for select
  using (is_approved() and is_my_tournament(tournament_id));
drop policy messages_insert on messages;
create policy messages_insert on messages for insert
  with check (is_approved() and user_id = auth.uid()
              and is_my_tournament(tournament_id));

-- ---------------------------------------------------------------------------
-- Group C: leaves keyed by slot_id.
-- ---------------------------------------------------------------------------

drop policy availability_select on availability;
create policy availability_select on availability for select
  using (is_approved() and is_my_slot(slot_id));
drop policy availability_insert on availability;
create policy availability_insert on availability for insert
  with check (
    is_approved() and user_id = auth.uid()
    and is_my_slot(slot_id)
    and not is_tournament_archived(
      (select tournament_id from slots where id = slot_id)
    )
  );

drop policy rosters_select on rosters;
create policy rosters_select on rosters for select
  using (is_approved() and is_my_slot(slot_id));
drop policy rosters_insert on rosters;
create policy rosters_insert on rosters for insert
  with check (
    is_approved() and added_by = auth.uid()
    and is_my_slot(slot_id)
    and not is_tournament_archived(
      (select tournament_id from slots where id = slot_id)
    )
  );
drop policy rosters_delete on rosters;
create policy rosters_delete on rosters for delete
  using (is_approved() and is_my_slot(slot_id));

-- ---------------------------------------------------------------------------
-- Group D: leaves keyed by order_id.
-- ---------------------------------------------------------------------------

drop policy order_slots_select on order_slots;
create policy order_slots_select on order_slots for select
  using (is_approved() and is_my_order(order_id));
drop policy order_slots_insert on order_slots;
create policy order_slots_insert on order_slots for insert
  with check (
    is_approved() and is_my_order(order_id)
    and not is_tournament_archived(
      (select tournament_id from orders where id = order_id)
    )
  );
drop policy order_slots_delete on order_slots;
create policy order_slots_delete on order_slots for delete
  using (is_approved() and is_my_order(order_id));

drop policy order_votes_select on order_votes;
create policy order_votes_select on order_votes for select
  using (is_approved() and is_my_order(order_id));
drop policy order_votes_insert on order_votes;
create policy order_votes_insert on order_votes for insert
  with check (
    is_approved() and user_id = auth.uid()
    and is_my_order(order_id)
    and not is_tournament_archived(
      (select tournament_id from orders where id = order_id)
    )
  );

-- Group E (unchanged, self-scoped user_id = auth.uid()): profiles_update_own,
-- availability_delete, order_votes_update, order_votes_delete,
-- messages_delete_own, chat_mutes_own, notification_prefs_own,
-- tournament_hides_own, team_messages_delete_own, team_chat_mutes_own.

-- ---------------------------------------------------------------------------
-- Team-scope the membership RPCs (were global — cross-team exploitable once
-- a second team exists).
-- ---------------------------------------------------------------------------

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
  where id = p_user_id and status = 'pending' and team_id = my_team();
end;
$$;

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
    where id = p_user_id and team_id = my_team();
  else
    update profiles set hidden_at = null
    where id = p_user_id and team_id = my_team();
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Team creation (self-service) and approval (superadmin only)
-- ---------------------------------------------------------------------------

create or replace function create_team(p_team_name text, p_display_name text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_team teams;
  v_profile profiles;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from profiles where id = v_uid) then
    raise exception 'already_member';
  end if;
  if trim(p_team_name) = '' then raise exception 'empty_team_name'; end if;
  if trim(p_display_name) = '' then raise exception 'empty_display_name'; end if;

  -- The REAL invite code is chosen by the superadmin at approval; until
  -- then an unguessable placeholder holds the unique slot (nobody can join
  -- a team whose code they can't know).
  insert into teams (name, invite_code, manage_pin)
  values (trim(p_team_name),
          'cekame-' || replace(gen_random_uuid()::text, '-', ''),
          lpad(floor(random() * 10000)::int::text, 4, '0'))
  returning * into v_team;

  -- The founder is approved WITHIN the team; the team itself still waits.
  insert into profiles (id, display_name, team_id, status, approved_at)
  values (v_uid, trim(p_display_name), v_team.id, 'approved', now())
  returning * into v_profile;

  -- FK to profiles — can only point at the founder after the row above.
  update teams set created_by = v_uid where id = v_team.id;

  return json_build_object('manage_pin', v_team.manage_pin);
end;
$$;

-- Approval names the team's invite code (the superadmin picks it).
create or replace function approve_team(p_team_id uuid, p_invite_code text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_superadmin() then raise exception 'not_superadmin'; end if;
  if trim(p_invite_code) = '' then raise exception 'empty_invite_code'; end if;
  if exists (select 1 from teams
             where lower(invite_code) = lower(trim(p_invite_code))
               and id <> p_team_id) then
    raise exception 'invite_code_taken';
  end if;
  update teams
  set invite_code = trim(p_invite_code),
      status = 'approved', approved_by = auth.uid(), approved_at = now()
  where id = p_team_id and status = 'pending';
end;
$$;

-- Push to the superadmin when a team is created (reuses the webhook fan-out).
create trigger notify_teams
  after insert on teams
  for each row execute function notify_webhook();

-- New notification kind for it. THREE-place sync rule: this CHECK,
-- NotificationKind in lib/domain/models.dart, and NotificationKind in
-- supabase/functions/notify/index.ts.
alter table notification_prefs drop constraint notification_prefs_kind_check;
alter table notification_prefs add constraint notification_prefs_kind_check
  check (kind in (
    'new_member', 'new_tournament', 'proposal', 'order', 'chat', 'threshold',
    'new_public_tournament', 'new_team'
  ));
