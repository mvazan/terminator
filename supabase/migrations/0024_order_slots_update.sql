-- Recording an order for a start that's already in an active order now ADDS
-- lanes to the existing row instead of creating a duplicate order — that
-- update needs a policy (mirrors insert). Additive, old clients unaffected.
create policy order_slots_update on order_slots for update
  using (is_approved() and is_my_order(order_id)
         and not is_tournament_archived(
           (select orders.tournament_id from orders
             where orders.id = order_slots.order_id)))
  with check (is_approved() and is_my_order(order_id)
              and not is_tournament_archived(
                (select orders.tournament_id from orders
                  where orders.id = order_slots.order_id)));
