-- Per-kind notification delivery level: loud (default) vs silent. Silent
-- pushes go to a no-sound/no-vibration Android channel — tray entry and
-- launcher badge dot only. Composes with the existing enabled/muted_until:
-- off = enabled=false; silent = enabled=true AND silent=true.
-- Old clients' upserts don't mention the column, so they leave it unchanged.
alter table notification_prefs
  add column silent boolean not null default false;
