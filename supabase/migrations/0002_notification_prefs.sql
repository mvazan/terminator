-- Per-user, per-kind notification preferences.
-- Missing row = enabled (the default). A row can disable a kind outright or
-- mute it until a timestamp (1h/3h/6h/12h/custom from the app).
-- The notify Edge Function checks these before sending; per-chat mutes in
-- chat_mutes still apply on top for the 'chat' kind.

create table notification_prefs (
  user_id uuid not null references profiles (id) on delete cascade,
  kind text not null check (kind in (
    'new_member',      -- someone waits for approval
    'new_tournament',  -- a tournament was created
    'proposal',        -- a proposal was created (voting)
    'order',           -- ordered / cancelled
    'chat',            -- chat messages (any chat)
    'threshold'        -- a slot reached min players
  )),
  enabled boolean not null default true,
  muted_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, kind)
);

alter table notification_prefs enable row level security;

create policy notification_prefs_own on notification_prefs for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
