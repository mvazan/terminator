-- Force every client onto 2.2.0 (build 42). The AuthGate blocks any app whose
-- build number is below app_config.min_build and shows the UpdateScreen
-- (Play link). 2.2.0 is a breaking release (closed day chats + RLS), so
-- everyone must update. Unknown/offline builds never block (see AuthGate).
update app_config set min_build = 42;
