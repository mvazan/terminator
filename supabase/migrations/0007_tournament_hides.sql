-- Per-user "not interested" hide for tournaments. Distinct from the global
-- tournaments.hidden_at (admin/manage soft-hide for the whole team): this row
-- hides a tournament only for the one member who created it — dropping it from
-- their tournament list and chats, and silencing its pushes for them. Others
-- are unaffected.
create table tournament_hides (
  user_id uuid not null references profiles (id) on delete cascade,
  tournament_id uuid not null references tournaments (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, tournament_id)
);

alter table tournament_hides enable row level security;

-- Each member manages only their own hides.
create policy tournament_hides_own on tournament_hides for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- The baseline's blanket grant only covered tables that existed then; new
-- tables need explicit grants (same as tournament_radar).
grant all on tournament_hides to authenticated, service_role;

-- Client streams its own hides via realtime, like chat_mutes.
alter publication supabase_realtime add table tournament_hides;
