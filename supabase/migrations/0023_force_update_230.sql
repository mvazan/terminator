-- Force-update the fleet to 2.3.0 (build 45): chat pushes flip to data-only
-- (rendered by the app, with the inline reply action) in the same deploy —
-- older builds would show no chat notification in the background at all.
-- Applied only after build 45 went live on the Play internal track.
update app_config set min_build = 45;
