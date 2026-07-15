/// Riverpod providers over Supabase.
///
/// Data strategy for a ~20-person team: stream whole (team-scoped) tables via
/// Supabase Realtime and filter/join client-side. Volumes are tiny; this
/// keeps the API surface minimal and every screen live-updating for free.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../domain/day_chat.dart';
import '../domain/heatmap.dart';
import '../domain/models.dart';
import '../scrape/scraper.dart';
import 'table_cache.dart';

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

/// Public, overridable view of the signed-in user's id — widgets that need it
/// in build (and their tests) read this instead of the raw Supabase getter.
final currentUserIdProvider = Provider<String?>((ref) => ref.watch(_userIdProvider));

/// Minimum build the backend still supports; older builds block on an
/// update screen. Null while unknown (network error → don't block anyone).
final minBuildProvider = FutureProvider<int?>((ref) async {
  try {
    final row =
        await _db.from('app_config').select('min_build').maybeSingle();
    return row?['min_build'] as int?;
  } catch (_) {
    return null; // unreachable/older backend — never lock users out
  }
});

/// The signed-in user's profile row (null while the user has no profile yet,
/// i.e. before entering the invite code). Live — flips when approved.
final myProfileProvider = StreamProvider<Profile?>((ref) {
  final uid = ref.watch(_userIdProvider);
  if (uid == null) return Stream.value(null);
  return cachedRows(
    key: 'my_profile',
    live: () => _db.from('profiles').stream(primaryKey: ['id']).eq('id', uid),
  ).map((rows) => rows.isEmpty ? null : Profile.fromJson(rows.first));
});

/// All members incl. hidden — only the manage mode needs this. Everyday UI
/// uses [membersProvider], which drops hidden members.
final allMembersProvider = StreamProvider<List<Profile>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'profiles',
    live: () => _db.from('profiles').stream(primaryKey: ['id']),
  ).map((rows) => rows.map(Profile.fromJson).toList()
    ..sort((a, b) => a.displayName.compareTo(b.displayName)));
});

final membersProvider = Provider<AsyncValue<List<Profile>>>((ref) {
  return ref.watch(allMembersProvider).whenData(
      (all) => all.where((p) => !p.isHidden).toList());
});

/// All teams visible to the caller: members see their own team, the
/// superadmin sees every team (needed for the approval UI).
final _teamsProvider = StreamProvider<List<Team>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'teams',
    live: () => _db.from('teams').stream(primaryKey: ['id']),
  ).map((rows) => rows.map(Team.fromJson).toList());
});

/// The caller's own team, live — the pending→approved flip re-routes the
/// AuthGate without a restart.
final myTeamProvider = Provider<Team?>((ref) {
  final teamId = ref.watch(myProfileProvider).value?.teamId;
  if (teamId == null) return null;
  return (ref.watch(_teamsProvider).value ?? const [])
      .where((t) => t.id == teamId)
      .firstOrNull;
});

/// Teams awaiting the superadmin's approval (empty for regular members —
/// RLS only shows them their own team).
final pendingTeamsProvider = Provider<List<Team>>((ref) =>
    [for (final t in ref.watch(_teamsProvider).value ?? const <Team>[])
      if (!t.approved) t]);

/// Shared PIN gating the hidden manage mode — the caller's own team's PIN.
final managePinProvider = FutureProvider<String?>((ref) async {
  if (ref.watch(_userIdProvider) == null) return null;
  return ref.watch(myTeamProvider)?.managePin;
});

/// Saved bowling alleys, reusable across tournaments.
final venuesProvider = StreamProvider<List<Venue>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'venues',
    live: () => _db.from('venues').stream(primaryKey: ['id']),
  ).map((rows) => rows.map(Venue.fromJson).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
});

/// One venue looked up from the live venues stream.
final venueByIdProvider = Provider.family<Venue?, String?>((ref, id) {
  if (id == null) return null;
  return (ref.watch(venuesProvider).value ?? const [])
      .where((v) => v.id == id)
      .firstOrNull;
});

/// venue id -> name, for cheaply labelling many tournaments at once (lists,
/// season timeline) without a family lookup per row.
final venueNamesProvider = Provider<Map<String, String>>((ref) {
  return {
    for (final v in ref.watch(venuesProvider).value ?? const [])
      v.id: v.name,
  };
});

/// tournament id -> interest counts for the list tiles (one pass, live).
/// Tournaments whose last day is already past — their list summaries stay
/// whole (history), while running/upcoming ones drop their past days.
Set<String> _endedTournamentIds(Ref ref, Day now) => {
      for (final t in ref.watch(allTournamentsProvider).value ?? const [])
        if (t.endsOn.isBefore(now)) t.id,
    };

final tournamentInterestProvider =
    Provider<Map<String, TournamentInterest>>((ref) {
  final now = Day.fromDateTime(DateTime.now());
  return interestByTournament(
    slots: ref.watch(slotsProvider).value ?? const [],
    availability: ref.watch(availabilityProvider).value ?? const [],
    today: now,
    endedTournamentIds: _endedTournamentIds(ref, now),
    uid: currentUserId,
  );
});

/// tournamentId -> count of ordered/confirmed slots — the "obj." on the list.
final orderedSlotsCountProvider = Provider<Map<String, int>>((ref) {
  final now = Day.fromDateTime(DateTime.now());
  return orderedSlotsByTournament(
    slots: ref.watch(slotsProvider).value ?? const [],
    orders: ref.watch(ordersProvider).value ?? const [],
    orderSlots: ref.watch(orderSlotsProvider).value ?? const {},
    today: now,
    endedTournamentIds: _endedTournamentIds(ref, now),
  );
});

/// Single tournament looked up from the live tournaments stream.
// Resolves from the UNFILTERED list so a tournament reached by explicit
// navigation (map pin, chat) still loads even when it's hidden for me —
// otherwise the detail screen waits forever on a null lookup.
final tournamentByIdProvider = Provider.family<Tournament?, String>(
  (ref, id) => (ref.watch(allTournamentsProvider).value ?? const [])
      .where((t) => t.id == id)
      .firstOrNull,
);

/// All tournaments incl. hidden — only the manage mode needs this. Everyday UI
/// uses [tournamentsProvider], which drops hidden ones.
final allTournamentsProvider = StreamProvider<List<Tournament>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'tournaments',
    live: () => _db.from('tournaments').stream(primaryKey: ['id']),
  ).map((rows) => rows.map(Tournament.fromJson).toList()
    ..sort((a, b) => a.startsOn.compareTo(b.startsOn)));
});

/// The caller's own "not interested" hides — tournament ids they've hidden for
/// themselves (distinct from the team-wide [Tournament.isHidden]).
final myHiddenTournamentsProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(_userIdProvider);
  if (uid == null) return Stream.value(const <String>{});
  return cachedRows(
    key: 'tournament_hides',
    live: () => _db
        .from('tournament_hides')
        .stream(primaryKey: ['user_id', 'tournament_id']).eq('user_id', uid),
  ).map((rows) => {for (final row in rows) row['tournament_id'] as String});
});

final tournamentsProvider = Provider<AsyncValue<List<Tournament>>>((ref) {
  final mine = ref.watch(myHiddenTournamentsProvider).value ?? const <String>{};
  return ref.watch(allTournamentsProvider).whenData((all) => all
      .where((t) => !t.isHidden && !mine.contains(t.id))
      .toList());
});

final slotsProvider = StreamProvider<List<Slot>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'slots',
    live: () => _db.from('slots').stream(primaryKey: ['id']),
  ).map((rows) => rows.map(Slot.fromJson).toList());
});

final availabilityProvider = StreamProvider<List<Availability>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'availability',
    live: () =>
        _db.from('availability').stream(primaryKey: ['slot_id', 'user_id']),
  ).map((rows) => rows.map(Availability.fromJson).toList());
});

final ordersProvider = StreamProvider<List<Order>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'orders',
    live: () => _db.from('orders').stream(primaryKey: ['id']),
  ).map((rows) => rows.map(Order.fromJson).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

/// order_id -> slot_id -> ordered lane count.
final orderSlotsProvider =
    StreamProvider<Map<String, Map<String, int>>>((ref) {
  if (ref.watch(_userIdProvider) == null) {
    return Stream.value(const <String, Map<String, int>>{});
  }
  return cachedRows(
    key: 'order_slots',
    live: () =>
        _db.from('order_slots').stream(primaryKey: ['order_id', 'slot_id']),
  ).map((rows) {
    final map = <String, Map<String, int>>{};
    for (final row in rows) {
      map.putIfAbsent(row['order_id'] as String,
          () => <String, int>{})[row['slot_id'] as String] =
          row['lanes'] as int;
    }
    return map;
  });
});

final orderVotesProvider = StreamProvider<List<OrderVote>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'order_votes',
    live: () =>
        _db.from('order_votes').stream(primaryKey: ['order_id', 'user_id']),
  ).map((rows) => rows.map(OrderVote.fromJson).toList());
});

final rostersProvider = StreamProvider<List<RosterEntry>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'rosters',
    live: () => _db.from('rosters').stream(primaryKey: ['id']),
  ).map((rows) => rows.map(RosterEntry.fromJson).toList());
});

// Day-chat membership side tables (closed day chats).
final dayChatFansProvider = StreamProvider<List<DayChatFan>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'day_chat_fans',
    live: () => _db
        .from('day_chat_fans')
        .stream(primaryKey: ['tournament_id', 'day', 'user_id']),
  ).map((rows) => rows.map(DayChatFan.fromJson).toList());
});

final dayChatLeaversProvider = StreamProvider<List<DayChatLeaver>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'day_chat_leavers',
    live: () => _db
        .from('day_chat_leavers')
        .stream(primaryKey: ['tournament_id', 'day', 'user_id']),
  ).map((rows) => rows.map(DayChatLeaver.fromJson).toList());
});

/// Membership per day chat, keyed like muteKey(tournamentId, day).
final dayChatMembershipProvider =
    Provider<Map<String, DayChatMembership>>((ref) => dayChatMembershipByChat(
          orders: ref.watch(ordersProvider).value ?? const [],
          orderSlots: ref.watch(orderSlotsProvider).value ?? const {},
          slots: ref.watch(slotsProvider).value ?? const [],
          rosters: ref.watch(rostersProvider).value ?? const [],
          fans: ref.watch(dayChatFansProvider).value ?? const [],
          leavers: ref.watch(dayChatLeaversProvider).value ?? const [],
        ));

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
  return cachedRows(
    key: 'messages',
    live: () => _db.from('messages').stream(primaryKey: ['id']),
  ).map((rows) => rows.map(ChatMessage.fromJson).toList());
});

/// Sentinel "tournament id" for the one team-wide chat, so it reuses the same
/// mute/read/unread machinery keyed on tournamentId. No real tournament UUID
/// collides with this literal. The team chat lives in its own `team_messages`
/// table (see 0008) — this id is only a UI/mute key, never sent to the server.
const teamChatId = teamChatSentinelId;

/// The team-wide chat, oldest first. Stored in its own table so old app
/// versions never see it.
final teamMessagesProvider = StreamProvider<List<ChatMessage>>((ref) {
  if (ref.watch(_userIdProvider) == null) return Stream.value(const []);
  return cachedRows(
    key: 'team_messages',
    live: () => _db
        .from('team_messages')
        .stream(primaryKey: ['id']).order('created_at', ascending: true),
  ).map((rows) => rows.map(ChatMessage.fromTeamJson).toList());
});

/// The caller's chat mutes as "tournamentId|day" keys ('' day = tournament
/// chat). The team chat is muted via a separate table, folded in here under the
/// [teamChatId] sentinel key so the UI can treat all mutes uniformly.
final myMutesProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(_userIdProvider);
  if (uid == null) return Stream.value(const <String>{});
  final teamMuted = ref.watch(_teamChatMutedProvider).value ?? false;
  return cachedRows(
    key: 'chat_mutes',
    live: () =>
        _db.from('chat_mutes').stream(primaryKey: ['id']).eq('user_id', uid),
  ).map((rows) => {
        for (final row in rows) '${row['tournament_id']}|${row['day'] ?? ''}',
        if (teamMuted) muteKey(teamChatId, null),
      });
});

/// Whether the caller has muted the team-wide chat (its own tiny table).
final _teamChatMutedProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(_userIdProvider);
  if (uid == null) return Stream.value(false);
  return cachedRows(
    key: 'team_chat_mutes',
    live: () => _db
        .from('team_chat_mutes')
        .stream(primaryKey: ['user_id']).eq('user_id', uid),
  ).map((rows) => rows.isNotEmpty);
});

String muteKey(String tournamentId, Day? day) =>
    '$tournamentId|${day?.toSql() ?? ''}';

/// Whether the realtime socket is connected — false covers both device-offline
/// and server-down, which is exactly what the offline banner cares about.
final realtimeConnectedProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();
  final rt = _db.realtime;
  controller.add(rt.isConnected);
  rt.onOpen(() {
    if (!controller.isClosed) controller.add(true);
  });
  rt.onClose((_) {
    if (!controller.isClosed) controller.add(false);
  });
  rt.onError((_) {
    if (!controller.isClosed) controller.add(false);
  });
  ref.onDispose(controller.close);
  return controller.stream;
});

/// The caller's notification preferences by kind (kinds without a stored row
/// are simply absent — treat as enabled via [NotificationPref.fallback]).
final myNotificationPrefsProvider =
    StreamProvider<Map<NotificationKind, NotificationPref>>((ref) {
  final uid = ref.watch(_userIdProvider);
  if (uid == null) return Stream.value(const {});
  return cachedRows(
    key: 'notification_prefs',
    live: () => _db
        .from('notification_prefs')
        .stream(primaryKey: ['user_id', 'kind']).eq('user_id', uid),
  ).map((rows) => {
        for (final row in rows.map(NotificationPref.fromJson)) row.kind: row,
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

  /// Demo-account sign-in for Google Play review: password login (no e-mail),
  /// used only for [AppConfig.demoEmail]. See AppConfig for why this exists.
  static Future<void> signInDemo() => _db.auth.signInWithPassword(
      email: AppConfig.demoEmail, password: AppConfig.demoPassword);

  static Future<void> signOut() async {
    // Wipe the offline cache so a signed-out device keeps no team data.
    await clearTableCache();
    await _db.auth.signOut();
  }

  static Future<void> joinTeam(String inviteCode, String displayName) =>
      _db.rpc('join_team', params: {
        'p_invite_code': inviteCode,
        'p_display_name': displayName,
      });

  /// Creates a new (pending) team; returns the generated manage PIN. The
  /// invite code doesn't exist yet — the superadmin names it at approval,
  /// and the founder then sees it in the Tým tab.
  static Future<String> createTeam(
      String teamName, String displayName) async {
    final result = await _db.rpc('create_team', params: {
      'p_team_name': teamName,
      'p_display_name': displayName,
    }) as Map<String, dynamic>;
    return result['manage_pin'] as String;
  }

  /// Superadmin only — names the team's invite code and activates it.
  static Future<void> approveTeam(String teamId, String inviteCode) =>
      _db.rpc('approve_team', params: {
        'p_team_id': teamId,
        'p_invite_code': inviteCode,
      });

  static Future<void> approveMember(String userId) =>
      _db.rpc('approve_member', params: {'p_user_id': userId});

  /// Soft-hide (or unhide) a member. Hiding also sends them back to pending,
  /// so unhiding alone won't let them back in — they must be re-approved.
  static Future<void> setMemberHidden(String userId, bool hidden) =>
      _db.rpc('set_member_hidden', params: {
        'p_user_id': userId,
        'p_hidden': hidden,
      });

  /// Soft-hide (or unhide) a tournament and, with it, its chats/orders.
  static Future<void> setTournamentHidden(String id, bool hidden) =>
      _db.from('tournaments').update({
        'hidden_at': hidden ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', id);

  /// Per-user "not interested" hide: drops the tournament from *my* list and
  /// chats and silences its pushes for me only — others are unaffected.
  /// Hiding also clears my availability ticks there (one-way; unhide does
  /// not restore them) — callers warn when ticks exist.
  static Future<void> setTournamentHiddenForMe(String id, bool hidden) async {
    final uid = currentUserId!;
    if (hidden) {
      await _db
          .from('tournament_hides')
          .upsert({'user_id': uid, 'tournament_id': id});
      await _clearMyAvailability(id);
    } else {
      await _db
          .from('tournament_hides')
          .delete()
          .eq('user_id', uid)
          .eq('tournament_id', id);
    }
  }

  /// Batch of hide/unhide changes, committed when eye mode closes — a
  /// constant number of round trips regardless of how many tournaments
  /// changed (upsert, slots lookup, availability delete, unhide delete).
  /// Hidden tournaments also get my availability cleared (see above).
  /// No-op when signed out (the dispose-time commit can race sign-out).
  static Future<void> setTournamentHidesBatch({
    required Set<String> hide,
    required Set<String> unhide,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    if (hide.isNotEmpty) {
      await _db.from('tournament_hides').upsert(
          [for (final id in hide) {'user_id': uid, 'tournament_id': id}]);
      await _clearMyAvailabilityIn(hide.toList());
    }
    if (unhide.isNotEmpty) {
      await _db
          .from('tournament_hides')
          .delete()
          .eq('user_id', uid)
          .inFilter('tournament_id', unhide.toList());
    }
  }

  /// Drops the caller's availability ticks in one tournament (own rows only —
  /// availability's delete policy allows exactly that).
  static Future<void> _clearMyAvailability(String tournamentId) =>
      _clearMyAvailabilityIn([tournamentId]);

  static Future<void> _clearMyAvailabilityIn(
      List<String> tournamentIds) async {
    final uid = currentUserId;
    if (uid == null || tournamentIds.isEmpty) return;
    final rows = await _db
        .from('slots')
        .select('id')
        .inFilter('tournament_id', tournamentIds);
    final ids = [for (final r in rows) r['id'] as String];
    if (ids.isEmpty) return;
    await _db
        .from('availability')
        .delete()
        .eq('user_id', uid)
        .inFilter('slot_id', ids);
  }

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

  static Future<String> createVenue(Map<String, dynamic> fields) async {
    final row = await _db
        .from('venues')
        .insert({...fields, 'created_by': currentUserId!})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> updateVenue(String id, Map<String, dynamic> fields) =>
      _db.from('venues').update(fields).eq('id', id);

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

  /// Archives a tournament and stamps the year onto its name (unless already
  /// there), so next season's fresh copy — created without a year — doesn't
  /// clash with the archived one.
  static Future<void> archiveTournament(Tournament t) {
    final year = t.startsOn.year;
    final name = t.name.contains('$year') ? t.name : '${t.name} $year';
    return updateTournament(t.id, {
      'archived_at': DateTime.now().toUtc().toIso8601String(),
      'name': name,
    });
  }

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

    final result = await scraper.fetch(Uri.parse(sourceUrl));
    final venueSlots = result.slots;
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
      // DO NOTHING on conflict — availability has no UPDATE policy (see
      // setAvailabilityBulk), and a racing double-tap would otherwise 42501.
      await _db.from('availability').upsert(
          {'slot_id': slotId, 'user_id': uid},
          ignoreDuplicates: true);
    } else {
      await _db
          .from('availability')
          .delete()
          .eq('slot_id', slotId)
          .eq('user_id', uid);
    }
  }

  /// Tick/untick many slots at once (whole-day select). ignoreDuplicates
  /// makes the upsert ON CONFLICT DO NOTHING — availability has no UPDATE
  /// policy, so the default DO UPDATE is rejected by RLS the moment any of
  /// the day's slots is already ticked.
  static Future<void> setAvailabilityBulk(
      List<String> slotIds, bool available) async {
    if (slotIds.isEmpty) return;
    final uid = currentUserId!;
    if (available) {
      await _db.from('availability').upsert(
          [for (final id in slotIds) {'slot_id': id, 'user_id': uid}],
          ignoreDuplicates: true);
    } else {
      await _db
          .from('availability')
          .delete()
          .eq('user_id', uid)
          .inFilter('slot_id', slotIds);
    }
  }

  static Future<void> createProposal({
    required String tournamentId,
    required Map<String, int> lanesBySlot, // slot_id -> ordered lanes
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
      for (final entry in lanesBySlot.entries)
        {
          'order_id': orderId,
          'slot_id': entry.key,
          'lanes': entry.value,
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

  // Closed day chats: invite a teammate as a fan, leave, or rejoin.
  static Future<void> inviteDayFan(
          String tournamentId, Day day, String userId) =>
      _db.rpc('invite_day_fan', params: {
        'p_tournament': tournamentId,
        'p_day': day.toSql(),
        'p_user': userId,
      });

  static Future<void> leaveDayChat(String tournamentId, Day day) =>
      _db.rpc('leave_day_chat',
          params: {'p_tournament': tournamentId, 'p_day': day.toSql()});

  static Future<void> rejoinDayChat(String tournamentId, Day day) =>
      _db.rpc('rejoin_day_chat',
          params: {'p_tournament': tournamentId, 'p_day': day.toSql()});

  static Future<void> sendMessage(String tournamentId, Day? day, String body) =>
      _db.from('messages').insert({
        'tournament_id': tournamentId,
        'day': day?.toSql(),
        'user_id': currentUserId!,
        'body': body,
      });

  static Future<void> sendTeamMessage(String body) =>
      _db.from('team_messages').insert({
        'user_id': currentUserId!,
        'body': body,
      });

  static Future<void> setTeamChatMuted(bool muted) async {
    final uid = currentUserId!;
    if (muted) {
      await _db.from('team_chat_mutes').upsert({'user_id': uid});
    } else {
      await _db.from('team_chat_mutes').delete().eq('user_id', uid);
    }
  }

  /// enabled=true + mutedUntil=null  -> back to normal (row upserted anyway,
  /// which is fine — it equals the default).
  static Future<void> setNotificationPref(
    NotificationKind kind, {
    required bool enabled,
    bool silent = false,
    DateTime? mutedUntil,
  }) =>
      _db.from('notification_prefs').upsert({
        'user_id': currentUserId!,
        'kind': kind.sqlName,
        'enabled': enabled,
        'silent': silent,
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
