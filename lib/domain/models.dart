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

  bool get isWeekend =>
      weekday == DateTime.saturday || weekday == DateTime.sunday;

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

enum ProfileStatus { pending, approved }

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.status,
    this.phone,
    this.fcmToken,
  });

  final String id;
  final String displayName;
  final ProfileStatus status;
  final String? phone;
  final String? fcmToken;

  bool get isApproved => status == ProfileStatus.approved;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        status: json['status'] == 'approved'
            ? ProfileStatus.approved
            : ProfileStatus.pending,
        phone: json['phone'] as String?,
        fcmToken: json['fcm_token'] as String?,
      );
}

class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    required this.venue,
    required this.kind,
    required this.startsOn,
    required this.endsOn,
    required this.minPlayers,
    required this.maxPlayers,
    required this.orderingContact,
    required this.notes,
    required this.createdBy,
    this.archivedAt,
  });

  final String id;
  final String name;
  final String venue;
  final String kind;
  final Day startsOn;
  final Day endsOn;
  final int minPlayers;
  final int? maxPlayers;
  final String orderingContact;
  final String notes;
  final String createdBy;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  /// Label used in the season timeline: "Vracov (dvojice)".
  String get timelineLabel => kind.isEmpty ? venue : '$venue ($kind)';

  factory Tournament.fromJson(Map<String, dynamic> json) => Tournament(
        id: json['id'] as String,
        name: json['name'] as String,
        venue: json['venue'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        startsOn: Day.parse(json['starts_on'] as String),
        endsOn: Day.parse(json['ends_on'] as String),
        minPlayers: json['min_players'] as int,
        maxPlayers: json['max_players'] as int?,
        orderingContact: json['ordering_contact'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        createdBy: json['created_by'] as String,
        archivedAt: json['archived_at'] == null
            ? null
            : DateTime.parse(json['archived_at'] as String),
      );
}

class Slot {
  const Slot({
    required this.id,
    required this.tournamentId,
    required this.date,
    required this.time,
  });

  final String id;
  final String tournamentId;
  final Day date;
  final HourMinute time;

  factory Slot.fromJson(Map<String, dynamic> json) => Slot(
        id: json['id'] as String,
        tournamentId: json['tournament_id'] as String,
        date: Day.parse(json['date'] as String),
        time: HourMinute.parse(json['time'] as String),
      );
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
        note: json['note'] as String? ?? '',
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
        note: json['note'] as String? ?? '',
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
/// SQL names must match the notification_prefs.kind check constraint and the
/// kind strings used by the notify Edge Function.
enum NotificationKind {
  newMember('new_member'),
  newTournament('new_tournament'),
  proposal('proposal'),
  order('order'),
  chat('chat'),
  threshold('threshold');

  const NotificationKind(this.sqlName);

  final String sqlName;

  static NotificationKind? tryParse(String value) {
    for (final kind in values) {
      if (kind.sqlName == value) return kind;
    }
    return null;
  }
}

/// A member's preference for one notification kind.
/// No stored row means "enabled" — [NotificationPref.fallback].
class NotificationPref {
  const NotificationPref({
    required this.kind,
    required this.enabled,
    this.mutedUntil,
  });

  final NotificationKind kind;
  final bool enabled;
  final DateTime? mutedUntil;

  static NotificationPref fallback(NotificationKind kind) =>
      NotificationPref(kind: kind, enabled: true);

  bool isMutedAt(DateTime now) =>
      mutedUntil != null && mutedUntil!.isAfter(now);

  /// Will a notification of this kind reach the user at [now]?
  bool isActiveAt(DateTime now) => enabled && !isMutedAt(now);

  factory NotificationPref.fromJson(Map<String, dynamic> json) =>
      NotificationPref(
        kind: NotificationKind.tryParse(json['kind'] as String) ??
            NotificationKind.chat,
        enabled: json['enabled'] as bool,
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
}
