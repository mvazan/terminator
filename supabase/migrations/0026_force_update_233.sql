-- Force-update the fleet to 2.3.3 (build 48): older builds still create
-- duplicate orders (no merge) and miss the chips UI. Pushed deliberately
-- ~45 min AFTER the Play upload so the update is actually downloadable
-- when the lock screen appears (earlier bumps locked people out for the
-- Play propagation window).
update app_config set min_build = 48;
