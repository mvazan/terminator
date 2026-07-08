-- Hiding a member now also sends them back to 'pending', so re-showing them
-- isn't enough — they must be approved again (and meanwhile they land on the
-- waiting screen). Move this behind a SECURITY DEFINER function and drop the
-- broad update policy/grant added in 0007 (which also let members edit each
-- other's display_name — unintended).
drop policy if exists profiles_hide on profiles;
revoke update (hidden_at) on profiles from authenticated;

-- Hide (status -> pending) or un-hide (clears the hidden flag only; the member
-- stays pending until someone approves them again). Approved members only.
create or replace function set_member_hidden(p_user_id uuid, p_hidden boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_approved() then
    raise exception 'not_approved';
  end if;

  if p_hidden then
    update profiles
    set hidden_at = now(), status = 'pending', approved_by = null,
        approved_at = null
    where id = p_user_id;
  else
    update profiles set hidden_at = null where id = p_user_id;
  end if;
end;
$$;
