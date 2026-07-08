import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';

/// Hidden "manage" mode: lets a member hide/unhide tournaments and people
/// without an admin/permissions layer. Deliberately obscure — you reach it by
/// long-pressing a screen title and entering the shared PIN. Unlock lasts for
/// the session (until the app restarts).
final manageUnlockedProvider =
    NotifierProvider<ManageUnlockedNotifier, bool>(ManageUnlockedNotifier.new);

class ManageUnlockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
  void lock() => state = false;
}

/// Long-press handler for a screen title: if already unlocked, offers to lock
/// again; otherwise asks for the PIN and unlocks on a match.
Future<void> handleManageGesture(BuildContext context, WidgetRef ref) async {
  if (ref.read(manageUnlockedProvider)) {
    final lock = await confirmDialog(
      context,
      title: 'Režim správy',
      message: 'Skrývání je odemčené. Zamknout?',
      confirmLabel: 'Zamknout',
    );
    if (lock) ref.read(manageUnlockedProvider.notifier).lock();
    return;
  }

  final pin = await ref.read(managePinProvider.future);
  if (pin == null || !context.mounted) return;

  final entered = await promptText(
    context,
    title: 'PIN',
    hint: 'PIN pro režim správy',
    keyboardType: TextInputType.number,
  );
  if (entered == null || !context.mounted) return;
  if (entered.trim() == pin) {
    ref.read(manageUnlockedProvider.notifier).unlock();
    snack(context, 'Režim správy odemčen.');
  } else {
    snack(context, 'Špatný PIN.');
  }
}
