/// Riverpod providers over Supabase.
///
/// Data strategy for a ~20-person team: stream whole (team-scoped) tables via
/// Supabase Realtime and filter/join client-side. Volumes are tiny; this
/// keeps the API surface minimal and every screen live-updating for free.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../scrape/scraper.dart';

SupabaseClient get _db => Supabase.instance.client;

final authStateProvider = StreamProvider<AuthState>(
  (ref) => _db.auth.onAuthStateChange,
);

String? get currentUserId => _db.auth.currentUser?.id;

/// The signed-in user's id, tracked through auth changes. Every RLS-protected
/// data stream watches this so it is *recreated* on sign-in.
///
/// Why this matters: `.stream()` fetches its initial snapshot from PostgREST
/// with whatever JWT is current at subscription time, and only re-fetches on a
/// socket reconnect — not on a plain token update. On the OTP-code login path
/// the app is already running with no session, so streams first opened as anon
/// return nothing (RLS) and never refill. Rebuilding them on sign-in reopens
/// each stream under the authenticated JWT. (The magic-link path avoids this
/// because the session exists before any stream is first read.)
final _userIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return currentUserId;
});

/// The signed-in user's profile row (null while the user has no profile yet,
/// i.e. before entering the invite code). Live — flips when approved.
final myProfileProvider = StreamProvider<Profile?>((ref) {
  final uid = ref.watch(_userIdProvider);
  if (uid == null) return Stream.value(null);
  return _db
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', uid)
      .map((rows) => rows.isEmpty ? null : Profile.fromJson(rows.first));
});

final membersProvider = StreamProvider<List<Profile>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db
      .from('profiles')
      .stream(primaryKey: ['id'])
      .map((rows) => rows.map(Profile.fromJson).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName)));
});

/// Single tournament looked up from the live tournaments stream.
final tournamentByIdProvider = Provider.family<Tournament?, String>(
  (ref, id) => (ref.watch(tournamentsProvider).value ?? const [])
      .where((t) => t.id == id)
      .firstOrNull,
);

final tournamentsProvider = StreamProvider<List<Tournament>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db
      .from('tournaments')
      .stream(primaryKey: ['id'])
      .map((rows) => rows.map(Tournament.fromJson).toList()
        ..sort((a, b) => a.startsOn.compareTo(b.startsOn)));
});

final slotsProvider = StreamProvider<List<Slot>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db.from('slots').stream(primaryKey: ['id']).map(
      (rows) => rows.map(Slot.fromJson).toList());
});

final availabilityProvider = StreamProvider<List<Availability>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db
      .from('availability')
      .stream(primaryKey: ['slot_id', 'user_id'])
      .map((rows) => rows.map(Availability.fromJson).toList());
});

final ordersProvider = StreamProvider<List<Order>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db.from('orders').stream(primaryKey: ['id']).map(
      (rows) => rows.map(Order.fromJson).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

/// order_id -> slot_id -> ordered places (null = the kind's lane capacity).
final orderSlotsProvider =
    StreamProvider<Map<String, Map<String, int?>>>((ref) {
  if (ref.watch(_userIdProvider) == null) {
    return Stream.value(const <String, Map<String, int?>>{});
  }
  return _db
      .from('order_slots')
      .stream(primaryKey: ['order_id', 'slot_id'])
      .map((rows) {
    final map = <String, Map<String, int?>>{};
    for (final row in rows) {
      map.putIfAbsent(row['order_id'] as String,
          () => <String, int?>{})[row['slot_id'] as String] =
          row['places'] as int?;
    }
    return map;
  });
});

final orderVotesProvider = StreamProvider<List<OrderVote>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db
      .from('order_votes')
      .stream(primaryKey: ['order_id', 'user_id'])
      .map((rows) => rows.map(OrderVote.fromJson).toList());
});

final rostersProvider = StreamProvider<List<RosterEntry>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db.from('rosters').stream(primaryKey: ['id']).map(
      (rows) => rows.map(RosterEntry.fromJson).toList());
});

/// Messages of one tournament (both the tournament chat and its day chats).
final messagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, tournamentId) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('tournament_id', tournamentId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(ChatMessage.fromJson).toList());
});

/// All messages — the chat list needs last-activity and unread counts across
/// every chat at once (same whole-table strategy as the other streams).
final allMessagesProvider = StreamProvider<List<ChatMessage>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .map((rows) => rows.map(ChatMessage.fromJson).toList());
});

/// The caller's mutes as "tournamentId|day" keys ('' day = tournament chat).
final myMutesProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(_userIdProvider);
  if (uid == null) return Stream.value(const <String>{});
  return _db
      .from('chat_mutes')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .map((rows) => {
            for (final row in rows)
              '${row['tournament_id']}|${row['day'] ?? ''}',
          });
});

String muteKey(String tournamentId, Day? day) =>
    '$tournamentId|${day?.toSql() ?? ''}';

/// The caller's notification preferences by kind (kinds without a stored row
/// are simply absent — treat as enabled via [NotificationPref.fallback]).
final myNotificationPrefsProvider =
    StreamProvider<Map<NotificationKind, NotificationPref>>((ref) {
  final uid = ref.watch(_userIdProvider);
  if (uid == null) return Stream.value(const {});
  return _db
      .from('notification_prefs')
      .stream(primaryKey: ['user_id', 'kind'])
      .eq('user_id', uid)
      .map((rows) => {
            for (final row in rows.map(NotificationPref.fromJson))
              row.kind: row,
          });
});

// ---------------------------------------------------------------------------
// Actions (writes)
// ---------------------------------------------------------------------------

class Api {
  static Future<void> sendMagicLink(String email, String redirectTo) =>
      _db.auth.signInWithOtp(email: email, emailRedirectTo: redirectTo);

  /// Fallback for mail apps that drop the code from the magic link
  /// (e.g. Seznam's in-app browser): the e-mail also carries a numeric
  /// code the user can type in.
  static Future<void> verifyEmailOtp(String email, String code) =>
      _db.auth.verifyOTP(type: OtpType.email, email: email, token: code);

  static Future<void> signOut() => _db.auth.signOut();

  static Future<void> joinTeam(String inviteCode, String displayName) =>
      _db.rpc('join_team', params: {
        'p_invite_code': inviteCode,
        'p_display_name': displayName,
      });

  static Future<void> approveMember(String userId) =>
      _db.rpc('approve_member', params: {'p_user_id': userId});

  static Future<void> updateMyName(String name) async {
    await _db
        .from('profiles')
        .update({'display_name': name}).eq('id', currentUserId!);
  }

  static Future<void> updateFcmToken(String? token) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db.from('profiles').update({'fcm_token': token}).eq('id', uid);
  }

  static Future<String> createTournament({
    required Map<String, dynamic> tournament,
    required List<Map<String, dynamic>> slotRows,
  }) async {
    final inserted = await _db
        .from('tournaments')
        .insert(tournament)
        .select('id')
        .single();
    final id = inserted['id'] as String;
    if (slotRows.isNotEmpty) {
      await _db.from('slots').insert([
        for (final row in slotRows) {...row, 'tournament_id': id},
      ]);
    }
    return id;
  }

  static Future<void> updateTournament(
          String id, Map<String, dynamic> fields) =>
      _db.from('tournaments').update(fields).eq('id', id);

  static Future<void> archiveTournament(String id) => updateTournament(
      id, {'archived_at': DateTime.now().toUtc().toIso8601String()});

  /// How long scraped occupancy stays fresh before an automatic re-sync.
  static const scrapeTtl = Duration(minutes: 30);

  static bool scrapeIsStale(Tournament t) =>
      t.scrapedAt == null ||
      DateTime.now().toUtc().difference(t.scrapedAt!.toUtc()) > scrapeTtl;

  /// Downloads the tournament's reservation page and upserts the slot grid
  /// with venue occupancy. Returns the number of starts found; throws with a
  /// human message when the page is unusable. No-op for unrecognized URLs.
  static Future<int> syncFromWeb({
    required String tournamentId,
    required String sourceUrl,
  }) async {
    final scraper = ScraperRegistry.forUrl(sourceUrl);
    if (scraper == null) return 0;

    final venueSlots = await scraper.fetch(Uri.parse(sourceUrl));
    if (venueSlots.isEmpty) {
      throw Exception('stránka neobsahuje rezervační tabulku');
    }

    await _db.from('slots').upsert(
      [
        for (final v in venueSlots)
          {
            'tournament_id': tournamentId,
            'date': v.date.toSql(),
            'time': v.time.toSql(),
            'venue_capacity': v.capacity,
            'venue_occupied': v.occupied,
          },
      ],
      onConflict: 'tournament_id,date,time',
    );
    await _db.from('tournaments').update({
      'scraped_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', tournamentId);
    return venueSlots.length;
  }

  static Future<void> addSlot(String tournamentId, Day date, HourMinute time) =>
      _db.from('slots').insert({
        'tournament_id': tournamentId,
        'date': date.toSql(),
        'time': time.toSql(),
      });

  static Future<void> deleteSlot(String slotId) =>
      _db.from('slots').delete().eq('id', slotId);

  static Future<void> setAvailability(String slotId, bool available) async {
    final uid = currentUserId!;
    if (available) {
      await _db
          .from('availability')
          .upsert({'slot_id': slotId, 'user_id': uid});
    } else {
      await _db
          .from('availability')
          .delete()
          .eq('slot_id', slotId)
          .eq('user_id', uid);
    }
  }

  static Future<void> createProposal({
    required String tournamentId,
    required Map<String, int> placesBySlot, // slot_id -> ordered places
    String note = '',
    bool directlyOrdered = false,
  }) async {
    final inserted = await _db
        .from('orders')
        .insert({
          'tournament_id': tournamentId,
          'created_by': currentUserId!,
          'note': note,
          'status': directlyOrdered ? 'ordered' : 'proposed',
          if (directlyOrdered)
            'ordered_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    final orderId = inserted['id'] as String;
    await _db.from('order_slots').insert([
      for (final entry in placesBySlot.entries)
        {
          'order_id': orderId,
          'slot_id': entry.key,
          'places': entry.value,
        },
    ]);
  }

  static Future<void> vote(String orderId, Vote vote, {String note = ''}) =>
      _db.from('order_votes').upsert({
        'order_id': orderId,
        'user_id': currentUserId!,
        'vote': vote.toSql(),
        'note': note,
      });

  static Future<void> setOrderStatus(String orderId, OrderStatus status) =>
      _db.from('orders').update({
        'status': status.name,
        if (status == OrderStatus.ordered)
          'ordered_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);

  static Future<void> joinSlot(String slotId, {String? userId}) =>
      _db.from('rosters').insert({
        'slot_id': slotId,
        'user_id': userId ?? currentUserId!,
        'added_by': currentUserId!,
      });

  static Future<void> addGuest(String slotId, String guestName) =>
      _db.from('rosters').insert({
        'slot_id': slotId,
        'guest_name': guestName,
        'added_by': currentUserId!,
      });

  static Future<void> removeRosterEntry(String rosterId) =>
      _db.from('rosters').delete().eq('id', rosterId);

  static Future<void> sendMessage(String tournamentId, Day? day, String body) =>
      _db.from('messages').insert({
        'tournament_id': tournamentId,
        'day': day?.toSql(),
        'user_id': currentUserId!,
        'body': body,
      });

  /// enabled=true + mutedUntil=null  -> back to normal (row upserted anyway,
  /// which is fine — it equals the default).
  static Future<void> setNotificationPref(
    NotificationKind kind, {
    required bool enabled,
    DateTime? mutedUntil,
  }) =>
      _db.from('notification_prefs').upsert({
        'user_id': currentUserId!,
        'kind': kind.sqlName,
        'enabled': enabled,
        'muted_until': mutedUntil?.toUtc().toIso8601String(),
      });

  static Future<void> setMuted(String tournamentId, Day? day, bool muted) async {
    final uid = currentUserId!;
    if (muted) {
      await _db.from('chat_mutes').insert({
        'user_id': uid,
        'tournament_id': tournamentId,
        'day': day?.toSql(),
      });
    } else {
      var query = _db
          .from('chat_mutes')
          .delete()
          .eq('user_id', uid)
          .eq('tournament_id', tournamentId);
      query = day == null
          ? query.isFilter('day', null)
          : query.eq('day', day.toSql());
      await query;
    }
  }
}
