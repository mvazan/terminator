-- Force-update the fleet to 2.2.2 (build 44): older builds sync scraped
-- occupancy with the pre-fix mkware parser (green booked rows invisible)
-- and would keep overwriting good data, and they miss the ours/ordered UI.
-- Applied only after build 44 went live on the Play internal track.
update app_config set min_build = 44;
