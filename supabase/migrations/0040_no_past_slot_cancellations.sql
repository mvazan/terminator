-- Zpětné "zrušení" odehraných dnů. Některé zdroje scrapingu (rezervační
-- stránky) skryjí den, jakmile se odehraje — starý klient jeho zmizení bral
-- jako zrušení kuželnou, orazítkoval cancelled_at a lidem se zájmem odešel
-- push "Kuželna zrušila termíny" o dnu, který dávno proběhl. Přitom odehrané
-- dny appka stejně skrývá; razítko jen falšuje historii (detail ukončeného
-- turnaje zrušené starty schovává, objednávka by ukazovala "zrušeno kuželnou").
-- Klient od příští verze minulé dny neruší; tady je serverová pojistka pro
-- staré buildy + oprava už poškozených řádků.

-- Pojistka: razítko dopadající na už odehraný den se zahodí dřív, než se
-- zapíše — AFTER trigger z 0037 pak nevidí žádný přechod a nic nezařadí do
-- fronty. Legitimní zrušení minulosti neexistuje: kuželna nemůže zrušit, co
-- se už odehrálo (jediný, kdo cancelled_at nastavuje, je scrape sync).
create or replace function slots_ignore_past_cancellation()
returns trigger
language plpgsql
as $$
begin
  if old.cancelled_at is null
     and new.cancelled_at is not null
     and new.date < (now() at time zone 'Europe/Prague')::date then
    new.cancelled_at := old.cancelled_at;
  end if;
  return new;
end;
$$;

create trigger slots_ignore_past_cancellation
  before update on slots
  for each row
  when (old.cancelled_at is distinct from new.cancelled_at)
  execute function slots_ignore_past_cancellation();

-- Oprava: razítka přišitá až po odehrání dne (datum razítka v Praze > datum
-- startu) jsou tenhle bug — skutečné zrušení se razítkuje nejpozději v den,
-- kterého se týká, a to zůstává. Přechod set→null projde triggerem z 0037,
-- který zároveň odzařadí případné ještě nerozeslané joby těch dnů.
update slots
   set cancelled_at = null
 where cancelled_at is not null
   and (cancelled_at at time zone 'Europe/Prague')::date > date;
