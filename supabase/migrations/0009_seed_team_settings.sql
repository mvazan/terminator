-- Seed the single team_settings row so a fresh project has an invite code
-- (previously inserted by hand during first setup — a gap that bit us when
-- moving regions). Idempotent: only inserts if the table is empty, so it
-- never overwrites an invite code or PIN changed later.
insert into team_settings (id, invite_code, manage_pin)
select true, 'veverky', '2468'
where not exists (select 1 from team_settings);
