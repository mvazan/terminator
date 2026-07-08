-- Discipline (throw format) as a second axis alongside kind. HS = "hry se
-- sdruženými" throw counts; "jiné" for anything else. Nullable — older
-- tournaments simply have none.
alter table tournaments add column discipline text
  check (discipline in ('60HS', '100HS', '120HS', '180HS', 'jiné'));

-- Organizer contacts live on the tournament (a venue can host several clubs
-- with different contacts). Keep only the venue's home-club website.
alter table venues drop column contact_email;
alter table venues drop column contact_phone;
