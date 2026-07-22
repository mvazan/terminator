-- Chat UX pack: delete own messages, reply threading, emoji reactions.
-- Additive — build 44 clients ignore all of it.

-- Deleting your own message (team_messages has this since 0008).
create policy messages_delete_own on messages for delete
  using (is_approved() and user_id = auth.uid());

-- Reply threading: a message may quote an earlier one in the same table.
alter table messages add column reply_to uuid references messages (id)
  on delete set null;
alter table team_messages add column reply_to uuid
  references team_messages (id) on delete set null;

-- Reactions, one table per chat namespace (mirrors the two message tables so
-- FK cascade + RLS stay honest). Visibility rides on "can I see the message"
-- — the exists() subquery evaluates the message table's own RLS.
create table message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references messages (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 8),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);
create index message_reactions_message_idx on message_reactions (message_id);
alter table message_reactions enable row level security;
create policy message_reactions_select on message_reactions for select
  using (is_approved()
         and exists (select 1 from messages m where m.id = message_id));
create policy message_reactions_insert on message_reactions for insert
  with check (is_approved() and user_id = auth.uid()
              and exists (select 1 from messages m where m.id = message_id));
create policy message_reactions_delete on message_reactions for delete
  using (user_id = auth.uid());
grant all on message_reactions to authenticated, service_role;

create table team_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references team_messages (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 8),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);
create index team_message_reactions_message_idx
  on team_message_reactions (message_id);
alter table team_message_reactions enable row level security;
create policy team_message_reactions_select on team_message_reactions
  for select using (is_approved()
    and exists (select 1 from team_messages m where m.id = message_id));
create policy team_message_reactions_insert on team_message_reactions
  for insert with check (is_approved() and user_id = auth.uid()
    and exists (select 1 from team_messages m where m.id = message_id));
create policy team_message_reactions_delete on team_message_reactions
  for delete using (user_id = auth.uid());
grant all on team_message_reactions to authenticated, service_role;

alter publication supabase_realtime add table message_reactions;
alter publication supabase_realtime add table team_message_reactions;
