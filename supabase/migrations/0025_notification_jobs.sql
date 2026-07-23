-- Deferred-notification engine: instead of pushing on every event, events
-- enqueue a JOB that fires a few minutes later. Three rules do all the work:
--   1. debounce  — same dedupe_key upserts (re-arms run_at), never duplicates;
--   2. undo      — the opposite action deletes the pending job (misclick =
--                  zero notifications, no add/remove ping-pong);
--   3. revalidate — the handler (notify EF) re-checks reality at send time,
--                  so a stale job can never send a wrong push.
-- First consumers: order free-spots digest, "you were assigned/removed".
-- Server-only — no client build needed, applies to every app version.

create table notification_jobs (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  dedupe_key text not null unique,
  payload jsonb not null default '{}'::jsonb,
  run_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index notification_jobs_due_idx on notification_jobs (run_at);
-- Server-only table: RLS on, no policies — clients can't touch it; the
-- security-definer helpers below and the service role do all the work.
alter table notification_jobs enable row level security;
grant all on notification_jobs to service_role;

create or replace function enqueue_notification(
  p_kind text, p_key text, p_payload jsonb,
  p_delay interval default interval '3 minutes')
returns void
language sql security definer set search_path = public
as $$
  insert into notification_jobs (kind, dedupe_key, payload, run_at)
  values (p_kind, p_key, p_payload, now() + p_delay)
  on conflict (dedupe_key)
    do update set run_at = excluded.run_at, payload = excluded.payload;
$$;

/** Deletes a pending job; true = one was actually waiting (the caller uses
 * that to implement the undo rule). */
create or replace function dequeue_notification(p_key text)
returns boolean
language plpgsql security definer set search_path = public
as $$
begin
  delete from notification_jobs where dedupe_key = p_key;
  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- Producers
-- ---------------------------------------------------------------------------

-- A new (or newly ordered) order: no immediate team push — the free-spots
-- digest fires after the creator had time to assign people. Full = silence.
create or replace function orders_enqueue_jobs()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.status = 'ordered' and
     (tg_op = 'INSERT' or old.status is distinct from new.status) then
    perform enqueue_notification('order_free_spots',
      'order_free_spots:' || new.id,
      jsonb_build_object('order_id', new.id));
  end if;
  return new;
end;
$$;
create trigger orders_enqueue_jobs
  after insert or update on orders
  for each row execute function orders_enqueue_jobs();

-- Roster changes drive three things: the assigned/removed personal notices
-- (with the undo rule against ping-pong) and a fresh free-spots check.
create or replace function rosters_enqueue_jobs()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_user uuid := coalesce(new.user_id, old.user_id);
  v_order uuid;
begin
  select o.id into v_order
    from order_slots os
    join orders o on o.id = os.order_id
    where os.slot_id = coalesce(new.slot_id, old.slot_id)
      and o.status in ('ordered', 'confirmed')
    limit 1;
  if v_order is null then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    -- Guests have no device; self-joins need no notice.
    if v_user is null or v_user = auth.uid() then return new; end if;
    -- Removed a moment ago and now back: net zero, tell them nothing.
    if dequeue_notification('removed:' || v_user || ':' || v_order) then
      return new;
    end if;
    perform enqueue_notification('assigned',
      'assigned:' || v_user || ':' || v_order,
      jsonb_build_object('order_id', v_order, 'user_id', v_user,
                         'added_by', new.added_by));
    return new;
  end if;

  -- DELETE: a place may have opened up — re-run the digest.
  perform enqueue_notification('order_free_spots',
    'order_free_spots:' || v_order,
    jsonb_build_object('order_id', v_order));
  if v_user is null or v_user = auth.uid() then return old; end if;
  -- Added a moment ago and now removed: they never knew — no ping-pong.
  if dequeue_notification('assigned:' || v_user || ':' || v_order) then
    return old;
  end if;
  perform enqueue_notification('removed',
    'removed:' || v_user || ':' || v_order,
    jsonb_build_object('order_id', v_order, 'user_id', v_user));
  return old;
end;
$$;
create trigger rosters_enqueue_jobs_ins
  after insert on rosters
  for each row execute function rosters_enqueue_jobs();
create trigger rosters_enqueue_jobs_del
  after delete on rosters
  for each row execute function rosters_enqueue_jobs();

-- ---------------------------------------------------------------------------
-- Consumer: a minutely cron pokes the notify EF only when something is due.
-- ---------------------------------------------------------------------------

create or replace function trigger_notification_jobs()
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from notification_jobs where run_at <= now()) then
    return;
  end if;
  perform net.http_post(
    url := 'https://txieiufeccpnnceunyxo.supabase.co/functions/v1/notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret()
    ),
    body := '{"type":"CRON","table":"notification_jobs","record":null,"old_record":null}'::jsonb
  );
end;
$$;

select cron.schedule('notification-jobs', '* * * * *',
  $$select trigger_notification_jobs()$$);
