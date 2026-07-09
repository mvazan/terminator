-- Tournament radar: a scheduled job scrapes public tournament listings and
-- pushes a notification for each newly-published one (opt-in, default off).

-- Remembers which public tournaments we've already seen, so the radar only
-- notifies about genuinely new ones. Keyed by (source, external_id).
create table tournament_radar (
  id uuid primary key default gen_random_uuid(),
  source text not null,            -- e.g. 'turnajekuzelky'
  external_id text not null,       -- the tournament id on that source
  name text not null,
  url text not null,
  discipline text,
  starts_on date,
  ends_on date,
  first_seen_at timestamptz not null default now(),
  unique (source, external_id)
);

-- Only the radar Edge Function (service role) touches this table; no client
-- access. RLS on with no policies = locked to authenticated/anon, like
-- team_settings. service_role must be granted explicitly — the baseline's
-- blanket grant only covered tables that existed then.
alter table tournament_radar enable row level security;
grant all on tournament_radar to service_role;

-- A new radar row → the notify function pushes "new public tournament" to
-- everyone who opted in. Reuses the existing webhook fan-out.
create trigger notify_tournament_radar
  after insert on tournament_radar
  for each row execute function notify_webhook();

-- New opt-in notification kind. The kind list lives in THREE places that must
-- stay in sync: this CHECK, NotificationKind in lib/domain/models.dart, and
-- NotificationKind + DEFAULT_OFF in supabase/functions/notify/index.ts.
alter table notification_prefs drop constraint notification_prefs_kind_check;
alter table notification_prefs add constraint notification_prefs_kind_check
  check (kind in (
    'new_member', 'new_tournament', 'proposal', 'order', 'chat', 'threshold',
    'new_public_tournament'
  ));
