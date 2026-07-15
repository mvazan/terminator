-- Day chats become closed groups: only people actually going that day (plus
-- invited fans and the order's creator) can read/write/get notified — instead
-- of spamming the whole team. Tournament chats (day is null) stay team-wide.
--
-- Membership is DERIVED, no materialization:
--   member := ( rostered on an active order's slot that day
--               OR creator of an active order for that day
--               OR has a day_chat_fans row )
--             AND NOT has a day_chat_leavers row
-- Fans are additive (any member can invite a teammate); leavers are
-- subtractive (anyone, incl. the organizer, can leave; rejoin removes it).

-- ---------------------------------------------------------------------------
-- Membership side tables
-- ---------------------------------------------------------------------------
create table day_chat_fans (
  tournament_id uuid not null references tournaments (id) on delete cascade,
  day date not null,
  user_id uuid not null references profiles (id) on delete cascade,
  added_by uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  primary key (tournament_id, day, user_id)
);

create table day_chat_leavers (
  tournament_id uuid not null references tournaments (id) on delete cascade,
  day date not null,
  user_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (tournament_id, day, user_id)
);

grant select on day_chat_fans to authenticated;
grant select on day_chat_leavers to authenticated;
grant all on day_chat_fans to service_role;
grant all on day_chat_leavers to service_role;

alter table day_chat_fans enable row level security;
alter table day_chat_leavers enable row level security;

-- Readable by the tournament's team (drives the client's live membership).
-- Writes go only through the SECURITY DEFINER RPCs below.
create policy day_chat_fans_select on day_chat_fans for select
  using (is_approved() and is_my_tournament(tournament_id));
create policy day_chat_leavers_select on day_chat_leavers for select
  using (is_approved() and is_my_tournament(tournament_id));

alter publication supabase_realtime add table day_chat_fans;
alter publication supabase_realtime add table day_chat_leavers;

-- ---------------------------------------------------------------------------
-- Membership helper — SECURITY DEFINER so it can join across orders/rosters
-- regardless of the caller's row visibility. The team check stays in the
-- policy (is_my_tournament), so this only decides day-membership.
-- ---------------------------------------------------------------------------
create or replace function is_day_member(p_tournament uuid, p_day date,
                                         p_uid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select
    -- Rostered players are always in (coordinating a game they play; they mute
    -- for quiet). Only the organizer / fans can leave.
    exists (
      select 1
      from orders o
      join order_slots os on os.order_id = o.id
      join slots s on s.id = os.slot_id
      join rosters r on r.slot_id = s.id
      where o.tournament_id = p_tournament
        and o.status in ('ordered', 'confirmed')
        and s.date = p_day
        and r.user_id = p_uid
    )
    or (
      not exists (
        select 1 from day_chat_leavers l
        where l.tournament_id = p_tournament and l.day = p_day
          and l.user_id = p_uid
      )
      and (
        exists ( -- creator of an active order for that day
          select 1
          from orders o
          join order_slots os on os.order_id = o.id
          join slots s on s.id = os.slot_id
          where o.tournament_id = p_tournament
            and o.status in ('ordered', 'confirmed')
            and s.date = p_day
            and o.created_by = p_uid
        )
        or exists ( -- explicitly invited fan
          select 1 from day_chat_fans f
          where f.tournament_id = p_tournament and f.day = p_day
            and f.user_id = p_uid
        )
      )
    );
$$;

-- The member set for a day chat — used by the notify function to target pushes
-- (author/muted are filtered there).
create or replace function day_member_ids(p_tournament uuid, p_day date)
returns table (user_id uuid)
language sql stable security definer set search_path = public
as $$
  -- Rostered players (always in).
  select distinct r.user_id
    from orders o
    join order_slots os on os.order_id = o.id
    join slots s on s.id = os.slot_id
    join rosters r on r.slot_id = s.id
    where o.tournament_id = p_tournament
      and o.status in ('ordered', 'confirmed')
      and s.date = p_day and r.user_id is not null
  union
  -- Creators and fans, minus those who left.
  select m.uid from (
    select o.created_by as uid
      from orders o
      join order_slots os on os.order_id = o.id
      join slots s on s.id = os.slot_id
      where o.tournament_id = p_tournament
        and o.status in ('ordered', 'confirmed')
        and s.date = p_day
    union
    select f.user_id from day_chat_fans f
      where f.tournament_id = p_tournament and f.day = p_day
  ) m
  where not exists (
    select 1 from day_chat_leavers l
    where l.tournament_id = p_tournament and l.day = p_day
      and l.user_id = m.uid
  );
$$;

-- ---------------------------------------------------------------------------
-- messages RLS: day chats gate on membership; tournament chats unchanged.
-- ---------------------------------------------------------------------------
drop policy messages_select on messages;
create policy messages_select on messages for select
  using (
    is_approved() and is_my_tournament(tournament_id)
    and (day is null or is_day_member(tournament_id, day, auth.uid()))
  );

drop policy messages_insert on messages;
create policy messages_insert on messages for insert
  with check (
    is_approved() and user_id = auth.uid()
    and is_my_tournament(tournament_id)
    and (day is null or is_day_member(tournament_id, day, auth.uid()))
  );
-- messages_delete_own (user_id = auth.uid()) stays as is.

-- ---------------------------------------------------------------------------
-- Membership RPCs (all guard team membership first)
-- ---------------------------------------------------------------------------

-- Invite a teammate as a fan of a day chat. Any current member may invite;
-- inviting clears the target's leaver row so the invite actually takes effect.
create or replace function invite_day_fan(p_tournament uuid, p_day date,
                                          p_user uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_my_tournament(p_tournament) then
    raise exception 'forbidden';
  end if;
  if not is_day_member(p_tournament, p_day, auth.uid()) then
    raise exception 'not_a_member';
  end if;
  if not exists (
    select 1 from profiles where id = p_user and team_id = my_team()
  ) then
    raise exception 'not_a_teammate';
  end if;
  delete from day_chat_leavers
    where tournament_id = p_tournament and day = p_day and user_id = p_user;
  insert into day_chat_fans (tournament_id, day, user_id, added_by)
    values (p_tournament, p_day, p_user, auth.uid())
    on conflict do nothing;
end;
$$;

-- Leave a day chat — universal opt-out (covers rostered/creator/fan). The fan
-- row (if any) is kept so rejoin restores it; the leaver row overrides.
create or replace function leave_day_chat(p_tournament uuid, p_day date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_my_tournament(p_tournament) then
    raise exception 'forbidden';
  end if;
  insert into day_chat_leavers (tournament_id, day, user_id)
    values (p_tournament, p_day, auth.uid())
    on conflict do nothing;
end;
$$;

create or replace function rejoin_day_chat(p_tournament uuid, p_day date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_my_tournament(p_tournament) then
    raise exception 'forbidden';
  end if;
  delete from day_chat_leavers
    where tournament_id = p_tournament and day = p_day
      and user_id = auth.uid();
end;
$$;
