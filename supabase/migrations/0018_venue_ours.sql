-- How many of a slot's occupied lanes are OURS — scraped occupancy whose
-- oddíl/team/klub text contains our team's name (case-insensitive). Lets the
-- app show "full because WE booked it" instead of blocking the slot: the UI
-- no longer hides full slots, it highlights ours and dims foreign-full ones.
-- Additive and nullable — old clients neither read nor write it.
alter table slots add column venue_occupied_ours int;
