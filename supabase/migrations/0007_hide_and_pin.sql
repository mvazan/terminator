-- Soft-hide for tournaments and members: set hidden_at to tuck them (and, for
-- a tournament, its chats/orders) out of the everyday UI without deleting
-- anything. Reversible. Filtered client-side — hiding is decluttering, not a
-- security boundary (the whole team is trusted).
alter table tournaments add column hidden_at timestamptz;
alter table profiles add column hidden_at timestamptz;

-- Shared PIN gating the hidden "manage" mode (unlock gesture + this PIN), so
-- not just anyone who knows the tap trick can hide things. Approved members
-- may read it; nobody writes it from the app (set once here / in the console).
alter table team_settings add column manage_pin text not null default '2468';

create policy team_settings_select on team_settings for select
  using (is_approved());

-- Approved members may hide/unhide any member (the manage mode is PIN-gated in
-- the app). Grant the new column and a policy for updating others' rows;
-- status/approved_* remain unreachable (still not in the grant).
grant update (hidden_at) on profiles to authenticated;

create policy profiles_hide on profiles for update
  using (is_approved()) with check (is_approved());

