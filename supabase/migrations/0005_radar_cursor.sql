-- Scan cursor for sources that have no listing page and are walked by id.
-- mkware (kkmoravskaslavia) serves each tournament at ?idt=N with no index, so
-- the radar remembers the highest id it has scanned and probes upward from
-- there each run. One row per source.
create table radar_cursor (
  source text primary key,
  last_id int not null
);

alter table radar_cursor enable row level security;
grant all on radar_cursor to service_role;

-- Seed mkware at the current highest live tournament (521 as of 2026-07-09) so
-- the radar only notifies about tournaments published from now on, not the
-- whole back-catalogue.
insert into radar_cursor (source, last_id) values ('mkware', 521)
on conflict (source) do nothing;
