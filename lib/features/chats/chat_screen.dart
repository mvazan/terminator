import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/local_prefs.dart';
import '../../data/providers.dart';
import '../../domain/chat_policy.dart';
import '../../domain/models.dart';

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

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await (widget.isTeam
          ? Api.sendTeamMessage(body)
          : Api.sendMessage(widget.tournamentId, widget.day, body));
      _input.clear();
    } catch (e) {
      if (mounted) {
        snack(
            context,
            isOfflineError(e)
                ? offlineMessage
                : 'Zprávu se nepovedlo odeslat: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    final mutes = ref.watch(myMutesProvider).value ?? const <String>{};
    final muted = mutes.contains(muteKey(widget.tournamentId, widget.day));

    // Everything rendered counts as read (also as new messages stream in
    // while the chat is open) — feeds the unread badges in the chat list.
    if (messages.isNotEmpty) {
      final latest = messages.last.createdAt;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(chatReadsProvider.notifier).markRead(
            muteKey(widget.tournamentId, widget.day), latest);
      });
    }

    final locked = tournament != null &&
        isChatLocked(
            tournament: tournament, day: widget.day, today: today());
    final title = widget.isTeam
        ? 'Celý tým'
        : (tournament == null
            ? 'Chat'
            : (widget.day == null
                ? tournament.name
                : '${tournament.name} — ${dayLabel(widget.day!)}'));
    final uid = currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('Zatím žádné zprávy.'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final message = messages[messages.length - 1 - i];
                      return _Bubble(
                        message: message,
                        mine: message.userId == uid,
                        author: memberName(members, message.userId),
                      );
                    },
                  ),
          ),
          if (!locked)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Napiš zprávu… (kdo veze auto?)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.author,
  });

  final ChatMessage message;
  final bool mine;
  final String author;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(message.createdAt.toLocal());
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(author,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.primary)),
            Text(message.body),
            Text(
              time.format(context),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
