-- Separate contact fields (e-mail + phone instead of one free-text field)
-- and web scraping support: tournaments can carry the organizer's
-- reservation-page URL; slots imported/refreshed from it carry venue
-- occupancy (how many lanes exist / are booked at the venue).

alter table tournaments
  add column contact_email text not null default '',
  add column contact_phone text not null default '',
  add column source_url text not null default '',
  add column scraped_at timestamptz;

alter table slots
  add column venue_capacity int,
  add column venue_occupied int;
