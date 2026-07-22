-- PostgREST truncates every response to max-rows (platform default 1000).
-- The whole-table Realtime streams load their initial snapshot as a single
-- select, so once a table outgrows the cap a cold start silently loses rows
-- (slots hit 2023 on 2026-07-22 and tournaments started showing only their
-- first few days). Clients from 2.2.1 page their snapshots and don't depend
-- on this ceiling; raising it fixes the 2.2.0 builds already in the field.
alter role authenticator set pgrst.db_max_rows = '10000';
notify pgrst, 'reload config';
