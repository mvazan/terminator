import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Day;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../core/ui.dart';
import '../data/providers.dart';
import '../domain/models.dart';
import '../features/chats/chat_screen.dart';
import '../features/tournaments/tournament_detail_screen.dart';

/// Push notifications via FCM.
///
/// Firebase is initialised from --dart-define values (no google-services.json
/// needed). Without them the whole module is a silent no-op, so the app
/// builds and runs before the Firebase project exists.
///
/// Tapping a notification routes to what it talks about: the tournament
/// detail, or the exact (day) chat. The route data comes from the FCM `data`
/// payload set by the notify Edge Function (kind + tournament_id + day).
class Push {
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Android notification channel ids — the loud default and the silent one.
  /// The notify Edge Function sends the matching id in `data['channel']` and
  /// `android.notification.channel_id`; keep the three places in sync.
  static const channelLoud = 'terminator';
  static const channelSilent = 'terminator_silent';

  /// Attached to the MaterialApp so notification taps can navigate.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Route from a tap that arrived before the main shell was on screen
  /// (cold start, or user not signed in/approved yet). Consumed by MainShell.
  static Map<String, dynamic>? _pendingRoute;
  static bool _shellReady = false;

  /// Set by MainShell so a tap can switch bottom-nav tabs (e.g. new_member →
  /// Tým). Indices match the tab order in MainShell.
  static void Function(int tab)? _switchTab;
  static const _teamTab = 3;

  static Future<void> init() async {
    if (!AppConfig.hasFirebase) {
      debugPrint('Push disabled: no FIREBASE_* dart-defines.');
      return;
    }
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _routeFromPayload(response.payload),
      );

      // Two explicit channels: the loud default and a silent one (tray entry
      // + launcher badge dot, no sound/vibration). The server routes each
      // push per recipient's per-kind preference via channel_id.
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        channelLoud,
        'Termínátor',
        description: 'Upozornění týmu',
        importance: Importance.high,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        channelSilent,
        'Termínátor (tiché)',
        description: 'Upozornění bez zvuku — jen lišta a tečka na ikoně',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ));

      await FirebaseMessaging.instance.requestPermission();

      // Save the token now (if signed in), on every sign-in, and on refresh.
      _ready = true;
      unawaited(_saveToken());
      Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedIn) unawaited(_saveToken());
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => _saveToken());

      // Foreground messages: show them via a local notification.
      FirebaseMessaging.onMessage.listen(_showForeground);

      // Tap on a system-tray notification while the app ran in background.
      FirebaseMessaging.onMessageOpenedApp
          .listen((message) => _route(message.data));

      // Tap that cold-started the app — FCM tray notification…
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingRoute = initial.data;
      // …or a locally shown (foreground) notification left in the tray.
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _routeFromPayload(launch!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('Push init failed (continuing without push): $e');
    }
  }

  /// MainShell reports when it's on screen (and how to switch tabs); a pending
  /// tap route fires then.
  static void shellReady(bool ready, {void Function(int tab)? switchTab}) {
    _shellReady = ready;
    _switchTab = ready ? switchTab : null;
    if (!ready) return;
    final pending = _pendingRoute;
    _pendingRoute = null;
    if (pending != null) _route(pending);
  }

  static void _routeFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      _route((jsonDecode(payload) as Map).cast<String, dynamic>());
    } catch (e) {
      debugPrint('Bad notification payload: $e');
    }
  }

  static void _route(Map<String, dynamic> data) {
    // A radar push carries an external URL — just open it in the browser.
    // Independent of the in-app nav, so it works even from a cold start.
    final url = data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      launchWeb(url);
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null || !_shellReady) {
      _pendingRoute = data; // fires once MainShell appears
      return;
    }

    // new_member has no tournament — it just points at the Tým tab, where
    // pending members get approved.
    if (data['kind'] == 'new_member') {
      navigator.popUntil((r) => r.isFirst); // back to the shell
      _switchTab?.call(_teamTab);
      return;
    }

    // The team-wide chat also has no tournament — open it directly.
    if (data['kind'] == 'team_chat') {
      navigator.push(MaterialPageRoute(builder: (_) => const ChatScreen.team()));
      return;
    }

    final tournamentId = data['tournament_id'] as String?;
    if (tournamentId == null) return;

    final day = data['day'] as String?;
    final Widget screen = data['kind'] == 'chat'
        ? ChatScreen(
            tournamentId: tournamentId,
            day: day == null ? null : Day.parse(day),
          )
        : TournamentDetailScreen(tournamentId: tournamentId);
    navigator.push(MaterialPageRoute(builder: (_) => screen));
  }

  static Future<void> _saveToken() async {
    if (!_ready) return;
    try {
      if (Supabase.instance.client.auth.currentUser == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      await Api.updateFcmToken(token);
    } catch (e) {
      debugPrint('FCM token save failed: $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    // Mirror the server-set FCM tag: same tag = replace in the tray
    // (a tournament never stacks e.g. threshold notifications).
    final tag = notification.android?.tag;
    // Honor the server's per-recipient channel choice (loud vs silent).
    final silent = message.data['channel'] == channelSilent;
    await _local.show(
      id: tag?.hashCode ?? notification.hashCode,
      title: notification.title,
      body: notification.body,
      payload: jsonEncode(message.data),
      notificationDetails: NotificationDetails(
        android: silent
            ? AndroidNotificationDetails(
                channelSilent,
                'Termínátor (tiché)',
                channelDescription:
                    'Upozornění bez zvuku — jen lišta a tečka na ikoně',
                importance: Importance.low,
                priority: Priority.defaultPriority,
                playSound: false,
                enableVibration: false,
                tag: tag,
              )
            : AndroidNotificationDetails(
                channelLoud,
                'Termínátor',
                channelDescription: 'Upozornění týmu',
                importance: Importance.high,
                priority: Priority.high,
                tag: tag,
              ),
      ),
    );
  }
}
