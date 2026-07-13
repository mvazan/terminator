-- Schedule the tournament radar twice a day (07:00 and 19:00 UTC). Each run
-- POSTs to the radar Edge Function via pg_net with the shared webhook secret;
-- the function scrapes the listing and inserts any new tournaments (which then
-- notify opted-in members through the existing trigger).
create extension if not exists pg_cron;

-- Wrapped in a function so the URL/secret live in one place.
create or replace function trigger_radar()
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://txieiufeccpnnceunyxo.supabase.co/functions/v1/radar',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret()
    ),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule('tournament-radar-morning', '0 7 * * *',
  $$select trigger_radar()$$);
select cron.schedule('tournament-radar-evening', '0 19 * * *',
  $$select trigger_radar()$$);
