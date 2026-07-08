-- Every tournament now picks a venue (all existing rows already have one).
alter table tournaments alter column venue_id set not null;
