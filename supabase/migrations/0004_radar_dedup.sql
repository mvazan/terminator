-- Cross-source dedup for the tournament radar. kuzelky.cz and turnajekuzelky.cz
-- have no shared id, so the same tournament can appear on both. We match them
-- fuzzily by a dedup_key = "starts_on|ends_on|NxMHS" (dates + discipline). When
-- a new entry's dedup_key was already seen (any source), we record it but don't
-- notify again. (source, external_id) still keeps per-source dedup exact.
alter table tournament_radar add column dedup_key text;
create index tournament_radar_dedup_idx on tournament_radar (dedup_key);

-- Set on rows that duplicate an already-seen tournament (same dedup_key from
-- another source): recorded for completeness but the notify trigger skips them.
alter table tournament_radar add column suppressed boolean not null default false;
