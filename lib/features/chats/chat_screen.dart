import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/local_prefs.dart';
import '../../data/providers.dart';
import '../../domain/chat_items.dart';
import '../../domain/chat_policy.dart';
import '../../domain/models.dart';
import '../tournaments/tournament_detail_screen.dart';

/// Emoji offered in the reaction picker (long-press a message).
const chatReactionEmoji = ['👍', '❤️', '😂', '😮', '🎳'];

/// One chat: the tournament chat (day == null), a day chat, or — when [isTeam]
/// is set — the standing team-wide chat (its own table, never locks).
/// Locked chats (subject passed + grace period) are read-only.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.tournamentId, this.day})
      : isTeam = false;

  /// The team-wide chat: no tournament, no day, never locked.
  const ChatScreen.team({super.key})
      : tournamentId = teamChatId,
        day = null,
        isTeam = true;

  final String tournamentId;
  final Day? day;
  final bool isTeam;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

/// An optimistically shown message: rendered immediately, replaced by the
/// real row once the stream delivers it (or flagged for retry on error).
class _Pending {
  _Pending(this.body, this.replyTo) : sentAt = DateTime.now().toUtc();
  final String body;
  final String? replyTo;
  final DateTime sentAt;
  bool failed = false;
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _pending = <_Pending>[];
  ChatMessage? _replyTo;
  ChatMessage? _editing;
  bool _showJump = false;
  Timer? _draftTimer;

  /// Read-state snapshot from BEFORE this visit — anchors the "Nové zprávy"
  /// divider so it doesn't jump away as markRead fires.
  DateTime? _dividerReadAt;
  var _dividerCaptured = false;

  String get _chatKey => muteKey(widget.tournamentId, widget.day);

  @override
  void initState() {
    super.initState();
    final drafts = ref.read(chatDraftsProvider);
    _input.text = drafts[_chatKey] ?? '';
    _input.addListener(_saveDraft);
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 600;
      if (show != _showJump) setState(() => _showJump = show);
    });
  }

  void _saveDraft() {
    if (_editing != null) return; // edited text is not a draft
    _draftTimer?.cancel();
    final text = _input.text;
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(chatDraftsProvider.notifier).set(_chatKey, text);
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // Persist whatever is typed right now, without the debounce.
    ref.read(chatDraftsProvider.notifier).set(_chatKey, _input.text);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    final editing = _editing;
    if (editing != null) {
      setState(() {
        _editing = null;
        _input.clear();
      });
      await tryAction(context,
          () => Api.editMessage(editing.id, body, team: widget.isTeam));
      return;
    }
    final pending = _Pending(body, _replyTo?.id);
    setState(() {
      _pending.add(pending);
      _replyTo = null;
      _input.clear();
    });
    ref.read(chatDraftsProvider.notifier).set(_chatKey, '');
    await _deliver(pending);
  }

  Future<void> _deliver(_Pending pending) async {
    try {
      await (widget.isTeam
          ? Api.sendTeamMessage(pending.body, replyTo: pending.replyTo)
          : Api.sendMessage(widget.tournamentId, widget.day, pending.body,
              replyTo: pending.replyTo));
    } catch (_) {
      if (mounted) setState(() => pending.failed = true);
    }
  }

  void _retry(_Pending pending) {
    setState(() => pending.failed = false);
    _deliver(pending);
  }

  /// Long-press actions: react, reply, copy, delete (own message only).
  void _messageActions(ChatMessage message, {required bool locked}) {
    final mine = message.userId == currentUserId;
    final reactions = _reactionsOf(message.id);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!locked)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in chatReactionEmoji)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _toggleReaction(message, emoji, reactions);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                  ],
                ),
              ),
            if (!locked && !mine)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Odpovědět'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() {
                    _replyTo = message;
                    _editing = null;
                  });
                },
              ),
            if (!locked && mine)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Upravit'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() {
                    _editing = message;
                    _replyTo = null;
                    _input.text = message.body;
                    _input.selection = TextSelection.collapsed(
                        offset: message.body.length);
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Kopírovat'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await Clipboard.setData(ClipboardData(text: message.body));
                if (mounted) snack(context, 'Zkopírováno.');
              },
            ),
            if (mine && !locked)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(sheetCtx).colorScheme.error),
                title: Text('Smazat',
                    style: TextStyle(
                        color: Theme.of(sheetCtx).colorScheme.error)),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await tryAction(
                      context,
                      () => Api.deleteMessage(message.id,
                          team: widget.isTeam),
                      success: 'Zpráva smazána.');
                },
              ),
          ],
        ),
      ),
    );
  }

  List<Reaction> _reactionsOf(String messageId) {
    final map = widget.isTeam
        ? ref.read(teamReactionsProvider).value
        : ref.read(reactionsProvider).value;
    return map?[messageId] ?? const [];
  }

  Future<void> _toggleReaction(
      ChatMessage message, String emoji, List<Reaction> current) async {
    final mine = current
        .any((r) => r.userId == currentUserId && r.emoji == emoji);
    await tryAction(
        context,
        () => Api.toggleReaction(message.id, emoji,
            team: widget.isTeam, mine: mine));
  }

  /// Day-chat membership sheet: who's in (players/organizer/fans), invite a
  /// fan, or leave (organizer/fans only — rostered players stay and mute).
  void _showMembers(List<Profile> members, bool locked) {
    final tId = widget.tournamentId;
    final day = widget.day!;
    final key = muteKey(tId, day);
    final uid = currentUserId;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => Consumer(builder: (ctx, ref2, _) {
        final m = ref2.watch(dayChatMembershipProvider)[key];
        final memberIds = m?.members.toList() ?? const <String>[];
        final iCanLeave = uid != null && (m?.canLeave(uid) ?? false);
        String roleLabel(String u) {
          if (m == null) return '';
          if (m.players.contains(u)) return 'hráč';
          if (m.creators.contains(u)) return 'organizátor';
          return 'fanoušek';
        }

        final candidates =
            members.where((p) => !memberIds.contains(p.id)).toList();
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kdo je tu (${memberIds.length})',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in memberIds)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_outline),
                          title: Text(memberName(members, u)),
                          trailing: Text(roleLabel(u),
                              style: TextStyle(color: scheme.outline)),
                        ),
                    ],
                  ),
                ),
                if (!locked) ...[
                  const Divider(),
                  if (candidates.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: const Text('Pozvat fanouška'),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _pickFan(candidates);
                      },
                    ),
                  if (iCanLeave)
                    ListTile(
                      leading: Icon(Icons.logout, color: scheme.error),
                      title: Text('Opustit chat',
                          style: TextStyle(color: scheme.error)),
                      onTap: () async {
                        Navigator.pop(sheetCtx);
                        final ok = await tryAction(
                            context, () => Api.leaveDayChat(tId, day),
                            success: 'Opustil jsi chat.');
                        if (ok && mounted) Navigator.of(context).maybePop();
                      },
                    ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }

  /// Pick a teammate to invite as a fan.
  Future<void> _pickFan(List<Profile> candidates) async {
    final choice = await showModalBottomSheet<Profile>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Pozvat fanouška',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in candidates)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(p.displayName),
                      onTap: () => Navigator.pop(ctx, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await tryAction(
      context,
      () => Api.inviteDayFan(widget.tournamentId, widget.day!, choice.id),
      success: '${choice.displayName} přidán(a) do chatu.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tournament = widget.isTeam
        ? null
        : ref.watch(tournamentByIdProvider(widget.tournamentId));
    final members = ref.watch(membersProvider).value ?? const [];
    final messages = widget.isTeam
        ? (ref.watch(teamMessagesProvider).value ?? const <ChatMessage>[])
        : (ref.watch(messagesProvider(widget.tournamentId)).value ??
                const <ChatMessage>[])
            .where((m) => m.day == widget.day)
            .toList();
    final reactions = (widget.isTeam
            ? ref.watch(teamReactionsProvider).value
            : ref.watch(reactionsProvider).value) ??
        const <String, List<Reaction>>{};
    final mutes = ref.watch(myMutesProvider).value ?? const <String>{};
    final muted = mutes.contains(_chatKey);
    final uid = currentUserId;

    // Snapshot the read state once, for the unread divider. The provider
    // loads from disk asynchronously, so wait for the first data.
    if (!_dividerCaptured) {
      final reads = ref.read(chatReadsProvider);
      if (reads.isNotEmpty || messages.isNotEmpty) {
        _dividerCaptured = true;
        _dividerReadAt = reads[_chatKey];
      }
    }

    // Everything rendered counts as read (also as new messages stream in
    // while the chat is open) — feeds the unread badges in the chat list.
    if (messages.isNotEmpty) {
      final latest = messages.last.createdAt;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(chatReadsProvider.notifier).markRead(_chatKey, latest);
      });
    }

    // Optimistic bubbles disappear once the stream carries the real row.
    _pending.removeWhere((p) =>
        !p.failed &&
        messages.any((m) =>
            m.userId == uid &&
            m.body == p.body &&
            !m.createdAt
                .isBefore(p.sentAt.subtract(const Duration(minutes: 2)))));

    final locked = tournament != null &&
        isChatLocked(
            tournament: tournament, day: widget.day, today: today());
    // Venue-first, like everywhere else — with the chat kind riding below.
    final venueName = tournament == null
        ? ''
        : (ref.watch(venueByIdProvider(tournament.venueId))?.name ?? '?');
    final title = widget.isTeam
        ? 'Celý tým'
        : (tournament == null
            ? 'Chat'
            : (widget.day == null
                ? venueName
                : '${dayLabel(widget.day!)}: $venueName'));
    final kindLine = widget.isTeam
        ? 'společný chat celé party'
        : (widget.day == null
            ? 'společný chat celého turnaje'
            : 'chat hracího dne');

    final byId = {for (final m in messages) m.id: m};
    final items = buildChatItems(messages, readAt: _dividerReadAt, uid: uid);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(kindLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          // Day chats are closed groups — show/manage who's in.
          if (!widget.isTeam && widget.day != null)
            IconButton(
              tooltip: 'Kdo je tu',
              icon: const Icon(Icons.groups_outlined),
              onPressed: () => _showMembers(members, locked),
            ),
          IconButton(
            tooltip: muted ? 'Zapnout upozornění' : 'Ztlumit',
            icon: Icon(muted
                ? Icons.notifications_off
                : Icons.notifications_active_outlined),
            onPressed: () => tryAction(
              context,
              () => widget.isTeam
                  ? Api.setTeamChatMuted(!muted)
                  : Api.setMuted(widget.tournamentId, widget.day, !muted),
              success: muted ? 'Upozornění zapnuta.' : 'Chat ztlumen.',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (locked)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(8),
              child: const Text('Chat je archivovaný (jen ke čtení).',
                  textAlign: TextAlign.center),
            ),
          if (widget.day != null && tournament != null)
            _DayContextBar(tournament: tournament, day: widget.day!),
          Expanded(
            child: Stack(
              children: [
                if (items.isEmpty && _pending.isEmpty)
                  const Center(child: Text('Zatím žádné zprávy.'))
                else
                  _messageList(items, byId, members, reactions, uid, locked),
                if (_showJump)
                  Positioned(
                    right: 12,
                    bottom: 8,
                    child: FloatingActionButton.small(
                      tooltip: 'Na konec',
                      onPressed: () => _scroll.animateTo(0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut),
                      child: const Icon(Icons.keyboard_double_arrow_down),
                    ),
                  ),
              ],
            ),
          ),
          if (!locked) _composer(byId, members),
        ],
      ),
    );
  }

  Widget _messageList(
    List<ChatItem> items,
    Map<String, ChatMessage> byId,
    List<Profile> members,
    Map<String, List<Reaction>> reactions,
    String? uid,
    bool locked,
  ) {
    // Ascending items + pending tail, rendered by a reversed list (index 0 =
    // bottom) so the view sticks to the newest message.
    final rendered = <Widget>[
      for (final item in items)
        switch (item) {
          DayHeaderItem(:final day) => _DayHeader(day: day),
          UnreadDividerItem() => const _UnreadDivider(),
          MessageItem(:final message, :final firstOfGroup, :final lastOfGroup) =>
            _Bubble(
              message: message,
              mine: message.userId == uid,
              author: memberName(members, message.userId),
              firstOfGroup: firstOfGroup,
              lastOfGroup: lastOfGroup,
              quoted: message.replyTo == null ? null : byId[message.replyTo],
              quotedAuthor: message.replyTo == null
                  ? null
                  : memberName(
                      members, byId[message.replyTo]?.userId ?? ''),
              reactions: reactions[message.id] ?? const [],
              uid: uid,
              onLongPress: () => _messageActions(message, locked: locked),
              onToggleReaction: (emoji) => _toggleReaction(
                  message, emoji, reactions[message.id] ?? const []),
            ),
        },
      for (final p in _pending)
        _PendingBubble(pending: p, onRetry: () => _retry(p)),
    ];
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: rendered.length,
      itemBuilder: (context, i) => rendered[rendered.length - 1 - i],
    );
  }

  Widget _composer(Map<String, ChatMessage> byId, List<Profile> members) {
    final replyTo = _replyTo;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editing != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Úprava zprávy',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  InkWell(
                    onTap: () => setState(() {
                      _editing = null;
                      _input.clear();
                    }),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          if (replyTo != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${memberName(members, replyTo.userId)}: '
                      '${replyTo.body.replaceAll('\n', ' ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _replyTo = null),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Napiš zprávu… (kdo veze auto?)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim context bar of a day chat: which starts the day has (from active
/// orders), how many lanes and who's rostered — tap opens the tournament.
class _DayContextBar extends ConsumerWidget {
  const _DayContextBar({required this.tournament, required this.day});

  final Tournament tournament;
  final Day day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = (ref.watch(ordersProvider).value ?? const [])
        .where((o) => o.tournamentId == tournament.id && o.isActive)
        .toList();
    final orderSlots =
        ref.watch(orderSlotsProvider).value ?? const <String, Map<String, int>>{};
    final slots = ref.watch(slotsProvider).value ?? const [];
    final slotById = {for (final s in slots) s.id: s};

    // Lanes per ordered slot on this day.
    final lanesBySlot = <String, int>{};
    for (final o in orders) {
      for (final e in (orderSlots[o.id] ?? const <String, int>{}).entries) {
        final slot = slotById[e.key];
        if (slot != null && slot.date == day) {
          lanesBySlot[e.key] = (lanesBySlot[e.key] ?? 0) + e.value;
        }
      }
    }
    if (lanesBySlot.isEmpty) return const SizedBox.shrink();

    final times = lanesBySlot.keys.map((id) => slotById[id]!).toList()
      ..sort(Slot.compare);
    final lanes = lanesBySlot.values.fold(0, (a, b) => a + b);
    final players = (ref.watch(rostersProvider).value ?? const [])
        .where((r) => lanesBySlot.containsKey(r.slotId))
        .length;

    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TournamentDetailScreen(
              tournamentId: tournament.id, scrollToOrders: true),
        ),
      ),
      child: Container(
        width: double.infinity,
        color: scheme.surfaceContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.receipt_long, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Start ${times.map((s) => s.time.display()).join(' + ')} · '
                '${lanesLabel(lanes)} · ${peopleLabel(players)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final Day day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          dayFull(day),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: scheme.primary)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Nové zprávy',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.primary),
            ),
          ),
          Expanded(child: Divider(color: scheme.primary)),
        ],
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.author,
    required this.firstOfGroup,
    required this.lastOfGroup,
    required this.reactions,
    required this.uid,
    this.quoted,
    this.quotedAuthor,
    this.onLongPress,
    this.onToggleReaction,
  });

  final ChatMessage message;
  final bool mine;
  final String author;
  final bool firstOfGroup;
  final bool lastOfGroup;

  /// The message this one replies to (null = plain, or original deleted).
  final ChatMessage? quoted;
  final String? quotedAuthor;
  final List<Reaction> reactions;
  final String? uid;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onToggleReaction;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  static final _urlPattern = RegExp(r'https?://[^\s]+');

  /// Body text with URLs tappable.
  List<InlineSpan> _linkify(String body, ColorScheme scheme) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _urlPattern.allMatches(body)) {
      if (match.start > index) {
        spans.add(TextSpan(text: body.substring(index, match.start)));
      }
      // Trailing punctuation belongs to the sentence, not the URL.
      var url = match.group(0)!;
      var end = match.end;
      while (url.isNotEmpty && '.,;:)]}'.contains(url[url.length - 1])) {
        url = url.substring(0, url.length - 1);
        end--;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => launchWeb(url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: url,
        recognizer: recognizer,
        style: TextStyle(
          color: widget.mine ? scheme.onPrimaryContainer : scheme.primary,
          decoration: TextDecoration.underline,
        ),
      ));
      index = end;
    }
    if (index < body.length) {
      spans.add(TextSpan(text: body.substring(index)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;
    final time = TimeOfDay.fromDateTime(message.createdAt.toLocal());

    // My reactions grouped: emoji → (count, includes me).
    final grouped = <String, ({int count, bool mine})>{};
    for (final r in widget.reactions) {
      final g = grouped[r.emoji];
      grouped[r.emoji] = (
        count: (g?.count ?? 0) + 1,
        mine: (g?.mine ?? false) || r.userId == widget.uid,
      );
    }

    return Align(
      alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            top: widget.firstOfGroup ? 6 : 1,
            bottom: widget.lastOfGroup ? 2 : 0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color:
                widget.mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.mine && widget.firstOfGroup)
                Text(widget.author,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.primary)),
              if (message.replyTo != null)
                Container(
                  margin: const EdgeInsets.only(top: 2, bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                        left: BorderSide(color: scheme.primary, width: 3)),
                  ),
                  child: Text(
                    widget.quoted == null
                        ? 'smazaná zpráva'
                        : '${widget.quotedAuthor}: '
                            '${widget.quoted!.body.replaceAll('\n', ' ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: widget.quoted == null
                            ? FontStyle.italic
                            : null),
                  ),
                ),
              Text.rich(TextSpan(children: _linkify(message.body, scheme))),
              if (grouped.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (final e in grouped.entries)
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: widget.onToggleReaction == null
                              ? null
                              : () => widget.onToggleReaction!(e.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: e.value.mine
                                  ? scheme.primary.withValues(alpha: 0.18)
                                  : scheme.surface.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                              border: e.value.mine
                                  ? Border.all(color: scheme.primary)
                                  : null,
                            ),
                            child: Text(
                              e.value.count == 1
                                  ? e.key
                                  : '${e.key} ${e.value.count}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (widget.lastOfGroup)
                Text(
                  time.format(context),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Optimistic bubble: shown the instant you hit send; a failure flips it to
/// the retry look.
class _PendingBubble extends StatelessWidget {
  const _PendingBubble({required this.pending, required this.onRetry});

  final _Pending pending;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: pending.failed ? onRetry : null,
        child: Opacity(
          opacity: pending.failed ? 1 : 0.6,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
              border:
                  pending.failed ? Border.all(color: scheme.error) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pending.body),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      pending.failed
                          ? Icons.error_outline
                          : Icons.schedule,
                      size: 12,
                      color: pending.failed ? scheme.error : null,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      pending.failed
                          ? 'Neodesláno — klepni pro nový pokus'
                          : 'Odesílám…',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                              color:
                                  pending.failed ? scheme.error : null),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
