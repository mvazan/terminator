-- Minimum supported build: the app checks this at startup and blocks with an
-- "update in Play" screen when it's older — the force-update lever for future
-- breaking releases. Single row; only the superadmin can raise it (via SQL or
-- a future UI). Readable pre-login so even a signed-out old build blocks.
create table app_config (
  id boolean primary key default true check (id),
  min_build int not null default 1
);

insert into app_config (min_build) values (1);

alter table app_config enable row level security;
create policy app_config_select on app_config for select using (true);
grant select on app_config to anon, authenticated;
grant all on app_config to service_role;
