-- Team-chat pushes: team_messages needs its own notify trigger — the webhook
-- fan-out is one trigger per table (see 0001), and 0008 added the table only.
create trigger notify_team_messages
  after insert on team_messages
  for each row execute function notify_webhook();
