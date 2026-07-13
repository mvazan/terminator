-- Webhook-secret rotation (GitGuardian: the old literal leaked via the public
-- repo). The secret now lives in Supabase Vault and the trigger functions read
-- it at call time — no secret ever appears in source again. The VALUE is
-- inserted manually, never committed:
--   select vault.create_secret('<value>', 'webhook_secret');
-- and the Edge Functions' env is rotated with:
--   supabase secrets set WEBHOOK_SECRET=<value>

create or replace function webhook_secret()
returns text
language sql stable security definer set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'webhook_secret';
$$;

-- Same body as 0001, secret swapped for the Vault lookup.
create or replace function notify_webhook()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://txieiufeccpnnceunyxo.supabase.co/functions/v1/notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret()
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

-- Same body as 0003, secret swapped for the Vault lookup.
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
