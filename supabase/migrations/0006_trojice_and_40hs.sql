-- Add 'trojice' (three players, one lane each) to the tournament kind list and
-- '40HS' to the discipline list. Mirror TournamentKind / Discipline in
-- lib/domain/models.dart.
alter table tournaments drop constraint tournaments_kind_check;
alter table tournaments add constraint tournaments_kind_check
  check (kind in ('jednotlivci', 'dvojice', 'trojice', 'čtveřice', 'tandem'));

alter table tournaments drop constraint tournaments_discipline_check;
alter table tournaments add constraint tournaments_discipline_check
  check (discipline in ('40HS', '60HS', '100HS', '120HS', '180HS', 'jiné'));
