import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/local_prefs.dart';
import '../../data/providers.dart';
import '../../domain/chat_policy.dart';
import '../../domain/models.dart';

/// One chat: the tournament chat (day == null) or a day chat.
/// Locked chats (subject passed + grace period) are read-only.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.tournamentId, this.day});

  final String tournamentId;
  final Day? day;

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
      await Api.sendMessage(widget.tournamentId, widget.day, body);
      _input.clear();
    } catch (e) {
      if (mounted) snack(context, 'Zprávu se nepovedlo odeslat: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tournament =
        ref.watch(tournamentByIdProvider(widget.tournamentId));
    final members = ref.watch(membersProvider).value ?? const [];
    final messages = (ref.watch(messagesProvider(widget.tournamentId)).value ??
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
    final title = tournament == null
        ? 'Chat'
        : (widget.day == null
            ? tournament.name
            : '${tournament.name} — ${dayLabel(widget.day!)}');
    final uid = currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: muted ? 'Zapnout upozornění' : 'Ztlumit',
            icon: Icon(muted
                ? Icons.notifications_off
                : Icons.notifications_active_outlined),
            onPressed: () => tryAction(
              context,
              () => Api.setMuted(widget.tournamentId, widget.day, !muted),
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
