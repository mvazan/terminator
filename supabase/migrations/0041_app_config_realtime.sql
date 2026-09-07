-- app_config do Realtime publikace — živý force-update.
--
-- Klient dosud četl min_build jednou při startu, takže bump zabral až po
-- zabití a znovuotevření appky; běžící starý build mezitím dál volal RPC
-- proti novému backendu a sypal do Sentry chyby. Od tohoto buildu appka
-- řádek app_config streamuje přes Realtime (+ znovu čte při návratu do
-- popředí a každých 5 minut jako zálohu), takže bump zamkne i běžící
-- appky do pár sekund. Tabulka je čitelná pre-login (0015), takže se
-- subscription otevře i pod anon rolí.
alter publication supabase_realtime add table app_config;
