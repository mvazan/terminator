import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/busy.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/chat_items.dart';
import '../../domain/models.dart';
import 'chat_list.dart';
import 'chat_screen.dart';

/// All chats: the team-wide chat pinned on top, tournament chats that have
/// messages, my day chats. Locked ones live in the archive section. Tiles
/// carry a last-message preview + relative time so the list is scannable
/// without opening anything.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(chatListProvider);
    final mutes = ref.watch(myMutesProvider).value ?? const <String>{};
    final members = ref.watch(membersProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Chaty')),
      body: ListView(
        children: [
          _ChatTile(
            data: model.team,
            mutes: mutes,
            members: members,
          ),
          const Divider(height: 1),
          for (final chat in model.open)
            _ChatTile(data: chat, mutes: mutes, members: members),
          if (model.archived.isNotEmpty)
            ExpansionTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text('Archiv (${model.archived.length})'),
              children: [
                for (final chat in model.archived)
                  _ChatTile(data: chat, mutes: mutes, members: members),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Text(
              'Prázdné chaty turnajů se nezobrazují — chat k turnaji '
              'otevřeš (a založíš) v jeho detailu.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({
    required this.data,
    required this.mutes,
    required this.members,
  });

  final ChatTileModel data;
  final Set<String> mutes;
  final List<Profile> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final t = data.tournament;
    final day = data.day;
    final isTeam = t == null;
    final muted = mutes.contains(data.key);
    final unread = data.unread;
    final uid = ref.watch(currentUserIdProvider);

    // Venue-first titles, same as tournaments — the team thinks in alleys.
    final title = isTeam
        ? 'Celý tým'
        : (day == null
            ? data.venueName
            : '${dayLabel(day)}: ${data.venueName}');
    final kindLine = isTeam
        ? 'společný chat celé party'
        : (day == null
            ? 'společný chat celého turnaje'
            : 'chat hracího dne · ${peopleLabel(data.memberCount ?? 0)}');

    // "Miloš: Beru auto o 15:30" — the last message, mine shown as "ty:".
    final last = data.lastMessage;
    final preview = last == null
        ? null
        : '${last.userId == uid ? 'ty' : memberName(members, last.userId)}: '
            '${last.body.replaceAll('\n', ' ')}';

    return ListTile(
      leading: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: Icon(
          isTeam ? Icons.forum : (day == null ? Icons.groups : Icons.event),
          color: isTeam ? scheme.primary : null,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isTeam ? scheme.primary : null,
          fontWeight: unread > 0
              ? FontWeight.w700
              : (isTeam ? FontWeight.w600 : null),
        ),
      ),
      isThreeLine: preview != null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kindLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  )),
          if (preview != null)
            Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: unread > 0
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (last != null)
            Text(
              chatListTime(last.createdAt, now: DateTime.now()),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: unread > 0 ? scheme.primary : scheme.outline,
                    fontWeight: unread > 0 ? FontWeight.w700 : null,
                  ),
            ),
          const SizedBox(width: 2),
          if (data.locked)
            const Icon(Icons.lock_outline, size: 16)
          else
            BusyIconButton(
              icon: Icon(
                muted
                    ? Icons.notifications_off
                    : Icons.notifications_active_outlined,
                size: 18,
              ),
              tooltip: muted ? 'Zapnout upozornění' : 'Ztlumit',
              onPressed: () async {
                await tryAction(
                    context,
                    () => isTeam
                        ? Api.setTeamChatMuted(!muted)
                        : Api.setMuted(t.id, day, !muted));
              },
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => isTeam
              ? const ChatScreen.team()
              : ChatScreen(tournamentId: t.id, day: day),
        ),
      ),
    );
  }
}
