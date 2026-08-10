-- Kalendář (0027) reagoval jen na změny rosteru a na zrušení objednávky.
-- Jenže roster řádky zrušení objednávky NEmaže — a tak když někdo na tentýž
-- slot vytvoří objednávku novou, starty jsou rázem zase „reálné", jenže
-- žádný roster se nezměnil a do kalendáře se nevrátily. Totéž platí pro
-- přidání slotu do běžící objednávky (top-up přes order_slots).
--
-- Oprava: sync se enqueuje i při NAVÁZÁNÍ slotu na aktivní objednávku.
-- Insert objednávky samotné nestačí — order_slots se vkládají až PO řádku
-- orders, takže fan-out přes ně musí viset na order_slots, ne na orders.
-- Handler je reconcile (0027), takže enqueue navíc nikdy nic nerozbije.

/** Slot se právě navázal na objednávku: pokud je aktivní, srovnej kalendáře
 * všech, kdo na slotu v rosteru už jsou. */
create or replace function order_slots_enqueue_calendar()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_roster record;
begin
  if exists (
    select 1 from orders o
      where o.id = new.order_id
        and o.status in ('ordered', 'confirmed')
  ) then
    for v_roster in
      select r.user_id from rosters r
        where r.slot_id = new.slot_id and r.user_id is not null
    loop
      perform enqueue_calendar_sync(v_roster.user_id, new.slot_id);
    end loop;
  end if;
  return new;
end;
$$;
create trigger order_slots_enqueue_calendar
  after insert on order_slots
  for each row execute function order_slots_enqueue_calendar();

-- A zrcadlově: objednávka změnila stav na aktivní (dnes se nové objednávky
-- rodí rovnou jako 'ordered' a order_slots přijdou až po nich — tuhle větev
-- pokrývá trigger výše; kdyby ale někdy vznikla cesta cancelled→ordered,
-- ať kalendáře nezůstanou pozadu). Stejné tělo jako 0027 + jedna smyčka.
create or replace function orders_enqueue_jobs()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_roster record;
begin
  if new.status = 'ordered' and
     (tg_op = 'INSERT' or old.status is distinct from new.status) then
    perform enqueue_notification('order_free_spots',
      'order_free_spots:' || new.id,
      jsonb_build_object('order_id', new.id));
    if tg_op = 'UPDATE' then
      for v_roster in
        select r.user_id, r.slot_id
          from order_slots os
          join rosters r on r.slot_id = os.slot_id
          where os.order_id = new.id and r.user_id is not null
      loop
        perform enqueue_calendar_sync(v_roster.user_id, v_roster.slot_id);
      end loop;
    end if;
  end if;

  if tg_op = 'UPDATE' and new.status = 'cancelled'
     and old.status is distinct from 'cancelled' then
    for v_roster in
      select r.user_id, r.slot_id
        from order_slots os
        join rosters r on r.slot_id = os.slot_id
        where os.order_id = new.id and r.user_id is not null
    loop
      perform enqueue_calendar_sync(v_roster.user_id, v_roster.slot_id);
    end loop;
  end if;

  return new;
end;
$$;
