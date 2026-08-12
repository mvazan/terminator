-- Add '240HS' to the discipline list (Hanácká 240 — 240 hodů sdružených).
-- Mirrors Discipline in lib/domain/models.dart.
alter table tournaments drop constraint tournaments_discipline_check;
alter table tournaments add constraint tournaments_discipline_check
  check (discipline in ('40HS', '60HS', '100HS', '120HS', '180HS', '240HS', 'jiné'));
