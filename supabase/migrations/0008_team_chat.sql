-- Team-wide chat: one standing conversation for the whole team, independent of
-- any tournament. Kept in its own table (not messages.tournament_id = null) so
-- older app versions — which stream the whole messages table and parse
-- tournament_id as non-null — never see these rows and can't crash on them.
create table team_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  body text not null check (body <> ''),
  created_at timestamptz not null default now()
);
create index team_messages_created_idx on team_messages (created_at);

alter table team_messages enable row level security;

-- Any approved member reads the team chat; you may only post as yourself.
create policy team_messages_select on team_messages for select
  using (is_approved());
create policy team_messages_insert on team_messages for insert
  with check (user_id = auth.uid() and is_approved());
create policy team_messages_delete_own on team_messages for delete
  using (user_id = auth.uid());

-- New table → explicit grants (the baseline blanket grant predates it).
grant all on team_messages to authenticated, service_role;

alter publication supabase_realtime add table team_messages;

-- Per-user mute for the team chat. Separate table because chat_mutes keys on a
-- tournament UUID (FK), which the team chat has none of.
create table team_chat_mutes (
  user_id uuid primary key references profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table team_chat_mutes enable row level security;
create policy team_chat_mutes_own on team_chat_mutes for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

grant all on team_chat_mutes to authenticated, service_role;
alter publication supabase_realtime add table team_chat_mutes;
