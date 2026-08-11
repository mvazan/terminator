-- The keep-alive workflow needs something the ANON role may touch. Tables
-- are authenticated-only by design (and stay that way), so the old ping
-- (select on tournaments) has returned 401 on every run since the team-RLS
-- hardening. This zero-data function is the one thing anon can call: it
-- exercises the API gateway AND the database, which is what the free-tier
-- pause heuristic counts.
create or replace function ping()
returns text
language sql stable
as $$ select 'ok' $$;

grant execute on function ping() to anon, authenticated;
