/// Domain models mirroring the Supabase schema (supabase/migrations).
/// Pure Dart — no Flutter imports — so all logic on top is unit-testable.
library;

/// A wall-clock time of day, independent of Flutter's TimeOfDay.
class HourMinute implements Comparable<HourMinute> {
  const HourMinute(this.hour, this.minute)
      : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  /// Parses "HH:MM" or "HH:MM:SS" (Postgres `time` format).
  factory HourMinute.parse(String value) {
    final parts = value.split(':');
    return HourMinute(int.parse(parts[0]), int.parse(parts[1]));
  }

  int get minutesFromMidnight => hour * 60 + minute;

  /// "HH:MM:SS" for Postgres.
  String toSql() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00';

  /// "H:MM" for people.
  String display() => '$hour:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(HourMinute other) =>
      minutesFromMidnight.compareTo(other.minutesFromMidnight);

  @override
  bool operator ==(Object other) =>
      other is HourMinute && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => display();
}

/// A calendar date without time-of-day. Wraps a UTC DateTime internally so
/// date arithmetic is DST-safe.
class Day implements Comparable<Day> {
  Day(int year, int month, int day) : _dt = DateTime.utc(year, month, day);

  Day.fromDateTime(DateTime dt) : _dt = DateTime.utc(dt.year, dt.month, dt.day);

  /// Parses "YYYY-MM-DD" (Postgres `date` format).
  factory Day.parse(String value) => Day.fromDateTime(DateTime.parse(value));

  final DateTime _dt;

  int get year => _dt.year;
  int get month => _dt.month;
  int get day => _dt.day;

  /// DateTime.monday (1) .. DateTime.sunday (7)
  int get weekday => _dt.weekday;

  Day addDays(int days) => Day.fromDateTime(_dt.add(Duration(days: days)));

  int differenceInDays(Day other) => _dt.difference(other._dt).inDays;

  bool isAfter(Day other) => _dt.isAfter(other._dt);
  bool isBefore(Day other) => _dt.isBefore(other._dt);

  String toSql() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(Day other) => _dt.compareTo(other._dt);

  @override
  bool operator ==(Object other) => other is Day && other._dt == _dt;

  @override
  int get hashCode => _dt.hashCode;

  @override
  String toString() => toSql();
}

/// Chronological ordering by date, then start time — the one comparator every
/// slot-like list in the app sorts by.
int compareDayTime(Day dateA, HourMinute timeA, Day dateB, HourMinute timeB) {
  final byDate = dateA.compareTo(dateB);
  return byDate != 0 ? byDate : timeA.compareTo(timeB);
}

/// "20.4.–3.5."
String rangeLabel(Day from, Day to) =>
    '${from.day}.${from.month}.–${to.day}.${to.month}.';

enum ProfileStatus { pending, approved }

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.status,
    this.fcmToken,
    this.hiddenAt,
  });

  final String id;
  final String displayName;
  final ProfileStatus status;
  final String? fcmToken;

  /// When set, the member is hidden from the everyday UI (soft, reversible).
  final DateTime? hiddenAt;

  bool get isApproved => status == ProfileStatus.approved;
  bool get isHidden => hiddenAt != null;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        status: json['status'] == 'approved'
            ? ProfileStatus.approved
            : ProfileStatus.pending,
        fcmToken: json['fcm_token'] as String?,
        hiddenAt: json['hidden_at'] == null
            ? null
            : DateTime.parse(json['hidden_at'] as String),
      );
}

/// Tournament format. Drives how many players fit on an ordered lane:
/// jednotlivci/dvojice/trojice/čtveřice put one player per lane; tandem is the
/// exception where two players share one lane. Stored labels are
/// CHECK-constrained in the tournaments table, so parsing never fails.
enum TournamentKind {
  jednotlivci('jednotlivci', 1),
  dvojice('dvojice', 1),
  trojice('trojice', 1),
  ctverice('čtveřice', 1),
  tandem('tandem', 2);

  const TournamentKind(this.label, this.playersPerLane);

  /// Czech display label, also the value stored in tournaments.kind.
  final String label;

  /// How many players occupy one lane. 1 for most kinds; tandem is the
  /// exception — 2 players share a single lane, so N lanes hold 2·N players.
  final int playersPerLane;

  static TournamentKind? tryParse(String value) {
    for (final kind in values) {
      if (kind.label == value) return kind;
    }
    return null;
  }
}

/// Throw format, a second axis alongside [TournamentKind]. HS = "hry se
/// sdruženými"; "jiné" covers anything else. Stored labels are
/// CHECK-constrained in the tournaments table.
enum Discipline {
  hs40('40HS'),
  hs60('60HS'),
  hs100('100HS'),
  hs120('120HS'),
  hs180('180HS'),
  other('jiné');

  const Discipline(this.label);

  final String label;

  static Discipline? tryParse(String? value) {
    if (value == null) return null;
    for (final d in values) {
      if (d.label == value) return d;
    }
    return null;
  }
}

class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    required this.venueId,
    required this.kind,
    this.discipline,
    required this.startsOn,
    required this.endsOn,
    required this.minPlayers,
    required this.contactEmail,
    required this.contactPhone,
    required this.sourceUrl,
    required this.notes,
    required this.createdBy,
    required this.createdAt,
    this.scrapedAt,
    this.archivedAt,
    this.hiddenAt,
  });

  final String id;
  final String name;

  /// The venue this tournament is played at (required). The name/address come
  /// from the venues table via this id — there's no denormalized copy.
  final String venueId;
  final TournamentKind kind;

  /// Throw format (60HS/100HS/…), independent of [kind]. Null = unset.
  final Discipline? discipline;
  final Day startsOn;
  final Day endsOn;
  final int minPlayers;
  final String contactEmail;
  final String contactPhone;

  /// Organizer's reservation page (scraping source). Empty = manual slots.
  final String sourceUrl;
  final DateTime? scrapedAt;
  final String notes;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? archivedAt;

  /// When set, the tournament (and its chats/orders) is hidden from the
  /// everyday UI (soft, reversible).
  final DateTime? hiddenAt;

  bool get isArchived => archivedAt != null;
  bool get isHidden => hiddenAt != null;

  /// Label used in the season timeline: "Vracov (dvojice)" or, with a
  /// discipline set, "Vracov (dvojice · 100HS)". The venue name is resolved
  /// from the venues table by the caller (via venueByIdProvider).
  String timelineLabel(String venueName) => discipline == null
      ? '$venueName (${kind.label})'
      : '$venueName (${kind.label} · ${discipline!.label})';

  factory Tournament.fromJson(Map<String, dynamic> json) => Tournament(
        id: json['id'] as String,
        name: json['name'] as String,
        venueId: json['venue_id'] as String,
        kind: TournamentKind.tryParse(json['kind'] as String) ??
            TournamentKind.dvojice,
        discipline: Discipline.tryParse(json['discipline'] as String?),
        startsOn: Day.parse(json['starts_on'] as String),
        endsOn: Day.parse(json['ends_on'] as String),
        minPlayers: json['min_players'] as int,
        contactEmail: json['contact_email'] as String,
        contactPhone: json['contact_phone'] as String,
        sourceUrl: json['source_url'] as String,
        scrapedAt: json['scraped_at'] == null
            ? null
            : DateTime.parse(json['scraped_at'] as String),
        notes: json['notes'] as String,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        archivedAt: json['archived_at'] == null
            ? null
            : DateTime.parse(json['archived_at'] as String),
        hiddenAt: json['hidden_at'] == null
            ? null
            : DateTime.parse(json['hidden_at'] as String),
      );
}

class Slot {
  const Slot({
    required this.id,
    required this.tournamentId,
    required this.date,
    required this.time,
    this.venueCapacity,
    this.venueOccupied,
  });

  final String id;
  final String tournamentId;
  final Day date;
  final HourMinute time;

  /// Lanes at the venue for this start / already booked there — known only
  /// for scraped tournaments (null = manual slot, no occupancy info).
  final int? venueCapacity;
  final int? venueOccupied;

  bool get hasVenueInfo => venueCapacity != null && venueOccupied != null;
  int? get venueFree => hasVenueInfo ? venueCapacity! - venueOccupied! : null;
  bool get venueFull => hasVenueInfo && venueOccupied! >= venueCapacity!;

  factory Slot.fromJson(Map<String, dynamic> json) => Slot(
        id: json['id'] as String,
        tournamentId: json['tournament_id'] as String,
        date: Day.parse(json['date'] as String),
        time: HourMinute.parse(json['time'] as String),
        venueCapacity: json['venue_capacity'] as int?,
        venueOccupied: json['venue_occupied'] as int?,
      );

  static int compare(Slot a, Slot b) =>
      compareDayTime(a.date, a.time, b.date, b.time);
}

/// Groups slots by their date, preserving input order within each day.
Map<Day, List<Slot>> slotsByDay(Iterable<Slot> slots) {
  final byDay = <Day, List<Slot>>{};
  for (final slot in slots) {
    byDay.putIfAbsent(slot.date, () => []).add(slot);
  }
  return byDay;
}

class Availability {
  const Availability({required this.slotId, required this.userId});

  final String slotId;
  final String userId;

  factory Availability.fromJson(Map<String, dynamic> json) => Availability(
        slotId: json['slot_id'] as String,
        userId: json['user_id'] as String,
      );
}

enum OrderStatus { proposed, ordered, confirmed, cancelled }

class Order {
  const Order({
    required this.id,
    required this.tournamentId,
    required this.createdBy,
    required this.status,
    required this.note,
    required this.createdAt,
    this.orderedAt,
  });

  final String id;
  final String tournamentId;
  final String createdBy;
  final OrderStatus status;
  final String note;
  final DateTime createdAt;
  final DateTime? orderedAt;

  bool get isProposal => status == OrderStatus.proposed;
  bool get isActive =>
      status == OrderStatus.ordered || status == OrderStatus.confirmed;

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        tournamentId: json['tournament_id'] as String,
        createdBy: json['created_by'] as String,
        status: OrderStatus.values.byName(json['status'] as String),
        note: json['note'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        orderedAt: json['ordered_at'] == null
            ? null
            : DateTime.parse(json['ordered_at'] as String),
      );
}

enum Vote { inn, out, otherDay }

extension VoteSql on Vote {
  String toSql() => switch (this) {
        Vote.inn => 'in',
        Vote.out => 'out',
        Vote.otherDay => 'other_day',
      };

  static Vote parse(String value) => switch (value) {
        'in' => Vote.inn,
        'out' => Vote.out,
        _ => Vote.otherDay,
      };
}

class OrderVote {
  const OrderVote({
    required this.orderId,
    required this.userId,
    required this.vote,
    this.note = '',
  });

  final String orderId;
  final String userId;
  final Vote vote;
  final String note;

  factory OrderVote.fromJson(Map<String, dynamic> json) => OrderVote(
        orderId: json['order_id'] as String,
        userId: json['user_id'] as String,
        vote: VoteSql.parse(json['vote'] as String),
        note: json['note'] as String,
      );
}

class RosterEntry {
  const RosterEntry({
    required this.id,
    required this.slotId,
    required this.addedBy,
    this.userId,
    this.guestName,
  });

  final String id;
  final String slotId;
  final String addedBy;
  final String? userId;
  final String? guestName;

  bool get isGuest => userId == null;

  factory RosterEntry.fromJson(Map<String, dynamic> json) => RosterEntry(
        id: json['id'] as String,
        slotId: json['slot_id'] as String,
        addedBy: json['added_by'] as String,
        userId: json['user_id'] as String?,
        guestName: json['guest_name'] as String?,
      );
}

/// Kinds of push notifications a member can tune in settings.
///
/// The kind list and the default-off rule live in THREE places that must stay
/// in sync (shared across runtimes, so full dedup isn't possible):
///   1. this enum (+ [defaultEnabled]),
///   2. supabase/functions/notify/index.ts — NotificationKind + DEFAULT_OFF,
///   3. supabase/migrations/0002_notification_prefs.sql — the kind CHECK
///      constraint (adding a kind needs a new migration extending it).
enum NotificationKind {
  newMember('new_member'),
  newTournament('new_tournament'),
  proposal('proposal'),
  order('order'),
  chat('chat'),
  threshold('threshold'),
  newPublicTournament('new_public_tournament');

  const NotificationKind(this.sqlName);

  final String sqlName;

  /// Whether the kind is on for members who never touched settings.
  /// newMember, threshold and newPublicTournament are opt-in.
  bool get defaultEnabled => !const {
        NotificationKind.newMember,
        NotificationKind.threshold,
        NotificationKind.newPublicTournament,
      }.contains(this);

  static NotificationKind? tryParse(String value) {
    for (final kind in values) {
      if (kind.sqlName == value) return kind;
    }
    return null;
  }
}

/// A member's preference for one notification kind.
/// No stored row means the kind's default — [NotificationPref.fallback].
class NotificationPref {
  const NotificationPref({
    required this.kind,
    required this.enabled,
    this.silent = false,
    this.mutedUntil,
  });

  final NotificationKind kind;
  final bool enabled;

  /// Delivered without sound/vibration — tray entry + launcher badge only.
  final bool silent;
  final DateTime? mutedUntil;

  static NotificationPref fallback(NotificationKind kind) =>
      NotificationPref(kind: kind, enabled: kind.defaultEnabled);

  bool isMutedAt(DateTime now) =>
      mutedUntil != null && mutedUntil!.isAfter(now);

  /// Will a notification of this kind reach the user at [now]?
  bool isActiveAt(DateTime now) => enabled && !isMutedAt(now);

  factory NotificationPref.fromJson(Map<String, dynamic> json) =>
      NotificationPref(
        kind: NotificationKind.tryParse(json['kind'] as String) ??
            NotificationKind.chat,
        enabled: json['enabled'] as bool,
        // Tolerates the pre-migration window where the column is absent.
        silent: json['silent'] as bool? ?? false,
        mutedUntil: json['muted_until'] == null
            ? null
            : DateTime.parse(json['muted_until'] as String),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.tournamentId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.day,
  });

  final String id;
  final String tournamentId;

  /// null = tournament chat, otherwise the day chat for that date.
  final Day? day;
  final String userId;
  final String body;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        tournamentId: json['tournament_id'] as String,
        day: json['day'] == null ? null : Day.parse(json['day'] as String),
        userId: json['user_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// A row from the separate `team_messages` table (the team-wide chat), which
  /// has no tournament/day — [teamChatSentinelId] stands in so it flows through
  /// the same chat UI and mute/read keys.
  factory ChatMessage.fromTeamJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        tournamentId: teamChatSentinelId,
        day: null,
        userId: json['user_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// See [teamChatId] in providers — kept here too so the model layer, which
/// can't import providers, can stamp team messages with the same sentinel.
const teamChatSentinelId = 'team';

class Venue {
  const Venue({
    required this.id,
    required this.name,
    required this.laneCount,
    required this.address,
    required this.sourceUrl,
    this.lat,
    this.lng,
  });

  final String id;
  final String name;

  /// Number of lanes at the alley. Required — everything else is optional.
  final int laneCount;
  final String address;

  /// Home club's website. Organizer contacts live on the tournament instead
  /// (one venue may host several clubs with different contacts).
  final String sourceUrl;

  /// Map coordinates, geocoded from [address] (null until geocoded).
  final double? lat;
  final double? lng;

  bool get hasCoords => lat != null && lng != null;

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
        id: json['id'] as String,
        name: json['name'] as String,
        laneCount: json['lane_count'] as int,
        address: json['address'] as String,
        sourceUrl: json['source_url'] as String,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );
}
