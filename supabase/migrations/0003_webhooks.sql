-- Webhooks: every event the notify Edge Function cares about is delivered by
-- a pg_net POST from these triggers. Kept as a migration (not dashboard
-- clicks) so the setup is reproducible from git.
-- The x-webhook-secret header must match the WEBHOOK_SECRET function secret.

create extension if not exists pg_net;

create or replace function notify_webhook()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://rpjfoopecntfyvmtrnfm.supabase.co/functions/v1/notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '3f3681ba6f2a83b0e2c0ad6f3619d27bb856d3ba8dd44ee4'
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', case when tg_op = 'DELETE' then null else to_jsonb(new) end,
      'old_record', case when tg_op = 'INSERT' then null else to_jsonb(old) end
    )
  );
  return coalesce(new, old);
end;
$$;

create trigger notify_profiles
  after insert on profiles
  for each row execute function notify_webhook();

create trigger notify_tournaments
  after insert on tournaments
  for each row execute function notify_webhook();

create trigger notify_orders
  after insert or update on orders
  for each row execute function notify_webhook();

create trigger notify_messages
  after insert on messages
  for each row execute function notify_webhook();

create trigger notify_availability
  after insert on availability
  for each row execute function notify_webhook();
