-- Synchronní odpojení kalendáře (EF calendar-manage) — schéma potřebuje jen
-- nový stav 'unlinked': řádek po odpojení PŘEŽÍVÁ (drží reminder_minutes,
-- ať se připomínky po novém propojení samy obnoví), jen bez e-mailu (PII)
-- a bez tokenů. Klienti 'unlinked' neznají a parse fallback ho čte jako
-- notLinked — dlaždice správně nabídne „Propojit", ale až KDYŽ je odpojení
-- doopravdy hotové: EF je synchronní, žádný cron, žádné okno pro závod,
-- který v 0031 nechával osiřelé kalendáře.
--
-- Starý asynchronní pár (RPC disconnect_calendar + job calendar_disconnect)
-- zůstává beze změny pro buildy <= 54; zahodit spolu s bumpnutím min_build.

alter table google_calendar_links drop constraint google_calendar_links_status_check;
alter table google_calendar_links add constraint google_calendar_links_status_check
  check (status in ('pending', 'linked', 'broken', 'disconnecting', 'unlinked'));
