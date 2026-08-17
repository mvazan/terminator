-- Day chats before the order exists: anyone who ticked interest in a day is a
-- member of that day's chat. The organizer can write to exactly the people who
-- said they want to play that day ("platí vám sobota?") without creating an
-- ad-hoc group and without pinging the whole team.
--
-- Membership becomes:
--   member := rostered on an active order's slot that day
--             OR ( ( ticked availability on a non-cancelled slot that day
--                    OR creator of an active order for that day
--                    OR has a day_chat_fans row )
--                  AND NOT has a day_chat_leavers row )
--
-- Interest is a LIVE source: unticking the day removes you from the chat (and
-- ticking adds you). It keeps applying after the order is placed, so nobody
-- drops out mid-conversation while the organizer is still filling the roster —
-- the non-rostered ones are exactly the people waiting for a free spot.
-- Rostered players still ignore leavers (they mute instead); interest, like
-- fans and creators, is leaver-subtractive, so "Opustit chat" still wins.

create or replace function is_day_member(p_tournament uuid, p_day date,
                                         p_uid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select
    -- Rostered players are always in (coordinating a game they play; they mute
    -- for quiet). Only the organizer / fans / interested can leave.
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
        exists ( -- ticked interest in that day (cancelled starts don't count)
          select 1
          from availability a
          join slots s on s.id = a.slot_id
          where s.tournament_id = p_tournament
            and s.date = p_day
            and s.cancelled_at is null
            and a.user_id = p_uid
        )
        or exists ( -- creator of an active order for that day
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
  -- Interested, creators and fans, minus those who left.
  select m.uid from (
    select a.user_id as uid
      from availability a
      join slots s on s.id = a.slot_id
      where s.tournament_id = p_tournament
        and s.date = p_day
        and s.cancelled_at is null
    union
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
