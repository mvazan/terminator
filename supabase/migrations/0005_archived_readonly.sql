-- Archived tournaments become read-only for everyone (enforced in the
-- database, not just hidden in the UI): no new/changed slots, availability,
-- proposals/orders/votes, or roster entries. Chat stays open — archiving a
-- tournament shouldn't also silence its coordination chat.

create or replace function is_tournament_archived(p_tournament_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select archived_at is not null
  from tournaments
  where id = p_tournament_id;
$$;

-- tournaments: writes to the tournament row itself must target a still-open
-- one, OR be the archive action itself (archived_at going from null to a
-- value). This still allows un-archiving later if ever needed.
drop policy if exists tournaments_all on tournaments;
create policy tournaments_select on tournaments for select
  using (is_approved());
create policy tournaments_insert on tournaments for insert
  with check (is_approved());
create policy tournaments_update on tournaments for update
  using (is_approved())
  with check (is_approved());
create policy tournaments_delete on tournaments for delete
  using (is_approved() and archived_at is null);

drop policy if exists slots_all on slots;
create policy slots_select on slots for select
  using (is_approved());
create policy slots_write on slots for insert
  with check (is_approved() and not is_tournament_archived(tournament_id));
create policy slots_update on slots for update
  using (is_approved() and not is_tournament_archived(tournament_id))
  with check (is_approved() and not is_tournament_archived(tournament_id));
create policy slots_delete on slots for delete
  using (is_approved() and not is_tournament_archived(tournament_id));

drop policy if exists availability_insert on availability;
create policy availability_insert on availability for insert
  with check (
    is_approved() and user_id = auth.uid()
    and not is_tournament_archived(
      (select tournament_id from slots where id = slot_id)
    )
  );
-- availability_delete stays as-is: un-ticking your own vote is harmless even
-- if a tournament somehow got archived while you had a stray tick.

drop policy if exists orders_all on orders;
create policy orders_select on orders for select
  using (is_approved());
create policy orders_write on orders for insert
  with check (is_approved() and not is_tournament_archived(tournament_id));
create policy orders_update on orders for update
  using (is_approved() and not is_tournament_archived(tournament_id))
  with check (is_approved() and not is_tournament_archived(tournament_id));
create policy orders_delete on orders for delete
  using (is_approved() and not is_tournament_archived(tournament_id));

drop policy if exists order_slots_all on order_slots;
create policy order_slots_select on order_slots for select
  using (is_approved());
create policy order_slots_write on order_slots for insert
  with check (
    is_approved()
    and not is_tournament_archived(
      (select tournament_id from orders where id = order_id)
    )
  );
create policy order_slots_delete on order_slots for delete
  using (is_approved());

drop policy if exists order_votes_insert on order_votes;
create policy order_votes_insert on order_votes for insert
  with check (
    is_approved() and user_id = auth.uid()
    and not is_tournament_archived(
      (select tournament_id from orders where id = order_id)
    )
  );
drop policy if exists order_votes_update on order_votes;
create policy order_votes_update on order_votes for update
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and not is_tournament_archived(
      (select tournament_id from orders where id = order_id)
    )
  );

drop policy if exists rosters_all on rosters;
create policy rosters_select on rosters for select
  using (is_approved());
create policy rosters_write on rosters for insert
  with check (
    is_approved() and added_by = auth.uid()
    and not is_tournament_archived(
      (select tournament_id from slots where id = slot_id)
    )
  );
create policy rosters_delete on rosters for delete
  using (is_approved());
