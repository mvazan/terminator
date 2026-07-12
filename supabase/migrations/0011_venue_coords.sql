-- Venue coordinates for the tournaments map. Nullable — filled by the app via
-- Nominatim geocoding of the address (on venue save, plus a lazy backfill from
-- the map screen for venues created before this).
alter table venues add column lat double precision;
alter table venues add column lng double precision;
