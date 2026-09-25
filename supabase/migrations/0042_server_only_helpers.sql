-- Interní pomocné funkce jen pro server.
--
-- webhook_secret, enqueue_notification, dequeue_notification,
-- enqueue_calendar_sync, trigger_radar a trigger_notification_jobs volají
-- výhradně security-definer triggery a pg_cron — obojí běží jako vlastník
-- (postgres), kterému EXECUTE zůstává. Appka ani
-- edge funkce je nevolají, přes Data API tedy nemají být dostupné nikomu.
-- Postgres dává EXECUTE roli PUBLIC u každé nové funkce a 0001 navíc
-- grantuje všechny tehdejší funkce authenticated a service_role — proto
-- revoke u všech čtyř.
--
-- create or replace práva zachová; kdyby některou z nich budoucí migrace
-- dropla a vytvořila znovu, musí tenhle revoke zopakovat.

revoke all on function webhook_secret()
  from public, anon, authenticated, service_role;
revoke all on function enqueue_notification(text, text, jsonb, interval)
  from public, anon, authenticated, service_role;
revoke all on function dequeue_notification(text)
  from public, anon, authenticated, service_role;
revoke all on function enqueue_calendar_sync(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function trigger_radar()
  from public, anon, authenticated, service_role;
revoke all on function trigger_notification_jobs()
  from public, anon, authenticated, service_role;
