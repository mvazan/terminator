# iOS — co dořešit, kdybychom někdy vydávali pro iPhone

Živý seznam. Appka je dnes Android-only (Google Play); kód míří na obě
platformy, ale některé věci jsou vědomě řešené jen pro Android. Když při
vývoji narazíš na další "na iOS by to chtělo X", připiš to sem — ať je
jednou při případném iOS vydání všechno na jednom místě.

## Push a notifikace

- **Data-only chat pushe.** Chatové zprávy jedou data-only a notifikaci
  kreslí appka (kvůli inline „Odpovědět"). Na iOS data-only FCM spolehlivě
  nebudí aplikaci (APNs `content-available` je throttlovaný, terminated
  stav nedoručí). Řešení pro iOS: APNs notification payload + Notification
  Service Extension, nebo chat pushe bez inline reply.
- **Inline „Odpovědět".** Android akce na notifikaci; iOS potřebuje
  registrovanou `UNNotificationCategory` s `UNTextInputNotificationAction`
  (v `DarwinInitializationSettings.notificationCategories`) a APNs
  `category` v payloadu.
- **Nahrazování notifikací (tag).** FCM `tag` je Android věc; na iOS je
  ekvivalent `apns-collapse-id` header. EF `notify` by ho musela posílat
  v `apns` sekci zprávy.
- **Úklid lišty při přečtení chatu.** `Push.clearChatNotifications` jde
  přes `AndroidFlutterLocalNotificationsPlugin.getActiveNotifications` a
  match podle payloadu; na iOS no-op. Ekvivalent: `UNUserNotificationCenter
  getDeliveredNotifications` + `removeDeliveredNotifications(withIdentifiers:)`
  (plugin: Darwin implementace / vlastní kanál).
- **Kanály loud/silent.** Per-příjemce hlasitost řeší Android notification
  channels (`terminator` / `terminator_silent`), server posílá
  `channel_id`. iOS kanály nemá — ticho se řeší per push (vynechat
  `sound` v APNs payloadu), EF by musela větvit podle platformy tokenu.
- **Badge (tečka na ikoně).** Na Androidu ji dělá kanál; na iOS se badge
  číslo nastavuje explicitně v payloadu (`apns.badge`) a musí se i
  nulovat (při čtení chatů / otevření appky).

## Ostatní

- **Force-update (`app_config.min_build`).** Mechanismus je
  cross-platform, ale hlášky a odkaz vedou na Google Play; pro iOS by
  bylo třeba App Store URL a oddělené min_buildy (build čísla obou
  platforem se nepotkávají).
- **Demo účet pro review.** Google Play review používá
  playreview@vvrky.cz + DEMO_PASSWORD bypass; Apple review by potřebovala
  totéž (funguje serverově, jen prověřit flow přihlášení na iOS).
