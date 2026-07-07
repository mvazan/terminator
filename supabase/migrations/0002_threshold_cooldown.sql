-- Threshold pushes are grouped per tournament: the first slot that crosses
-- min_players sends one summary push listing every currently-orderable slot,
-- then the tournament goes quiet for a cooldown window (slots crossing during
-- it are absorbed silently — they were part of the same ticking wave).
-- The notify Edge Function flips this atomically (compare-and-set).
alter table tournaments add column threshold_notified_at timestamptz;
