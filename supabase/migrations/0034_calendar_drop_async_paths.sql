-- Úklid po přechodu na synchronní kalendářové akce.
--
-- Odpojení i změna připomínek jsou od 2.7.0 (build 55) požadavky, na které
-- appka čeká — dělá je EF calendar-manage a vrátí výsledek. Odložené cesty
-- k témuž (0029/0030 `calendar_reminders`, 0031 `calendar_disconnect`)
-- zbyly jen pro starší buildy a nesou s sebou i tu chybu, kvůli které
-- vznikaly osiřelé kalendáře: minutu trvající okno, ve kterém dlaždice
-- nabízela „Propojit" dřív, než se stihl smazat starý kalendář.
--
-- Proto je rušíme spolu s force-updatem na build 55 (vzor 0026): starý
-- build se po něm ani nespustí, takže nemá kdo tyhle RPC volat. Děláme to
-- teď, dokud kalendář nikdo z týmu nepoužívá — jediní dva propojení jsou
-- testovací účty. Za měsíc by to znamenalo migrovat cizí data.
--
-- Zůstává jediný kalendářový job `calendar_sync` — ten je nenahraditelný:
-- reaguje na změny, které vyvolal NĚKDO JINÝ (přidal tě do sestavy, zrušil
-- objednávku), takže není žádný „tvůj" request, ve kterém by se to dalo
-- udělat rovnou.

-- Nedokončené joby zrušených druhů: handlery pro ně mizí, ať v tabulce
-- neleží věčně (processJobs by je jen logoval jako neznámé).
delete from notification_jobs
  where kind in ('calendar_reminders', 'calendar_disconnect');

drop function if exists disconnect_calendar();
drop function if exists set_calendar_reminders(text);
drop function if exists set_calendar_reminders(int[]);

-- Stav 'disconnecting' byl mezistav odloženého odpojení; synchronní cesta
-- přechází rovnou z 'linked' na 'unlinked'.
update google_calendar_links set status = 'unlinked' where status = 'disconnecting';
alter table google_calendar_links drop constraint google_calendar_links_status_check;
alter table google_calendar_links add constraint google_calendar_links_status_check
  check (status in ('pending', 'linked', 'broken', 'unlinked'));

-- Force-update na 2.7.0 (build 55). Pouštět až ~45 minut po nahrání na
-- Play, ať je aktualizace opravdu ke stažení, když se lidem objeví zámek.
update app_config set min_build = 55;
