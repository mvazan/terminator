-- How many places were actually ordered for a start. The team often orders
-- more than the currently signed-up players (someone joins later, or a slot
-- gets two lanes), so the count is entered when recording the order.
-- null = the tournament kind's lane capacity (dvojice = 2, …).
alter table order_slots add column places int check (places > 0);
