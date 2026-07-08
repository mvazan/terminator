-- Kuželny (bowling alleys). Reused across tournaments so the lane count and
-- address are entered once. Only the lane count is required; the rest is
-- optional. Tournaments reference a venue; the free-text `venue` name column
-- stays as a fallback for older rows / quick one-offs.
create table venues (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  lane_count int not null check (lane_count > 0),
  address text not null default '',
  contact_email text not null default '',
  contact_phone text not null default '',
  source_url text not null default '',
  created_by uuid not null references profiles (id),
  created_at timestamptz not null default now()
);

alter table tournaments add column venue_id uuid references venues (id);

alter table venues enable row level security;

create policy venues_select on venues for select
  using (is_approved());
create policy venues_insert on venues for insert
  with check (is_approved());
create policy venues_update on venues for update
  using (is_approved()) with check (is_approved());
-- No delete policy: a venue may be referenced by tournaments; keep it around.

alter publication supabase_realtime add table venues;
