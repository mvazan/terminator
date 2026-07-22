-- Editing your own chat message (both chat namespaces). Additive.
create policy messages_update_own on messages for update
  using (is_approved() and user_id = auth.uid())
  with check (is_approved() and user_id = auth.uid());
create policy team_messages_update_own on team_messages for update
  using (is_approved() and user_id = auth.uid())
  with check (is_approved() and user_id = auth.uid());
