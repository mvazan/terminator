import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// One cell of the availability heatmap: start time and, below it, how many
/// of our team ticked this slot. When the tournament is scraped, the count
/// reads "team/free" — team members available over free lanes at the venue
/// (team can exceed capacity). A check icon marks "enough people to order"
/// (orderable); a thick primary border marks MY tick. A home icon marks
/// occupancy booked by US on the venue's site; a foreign-full slot is dimmed
/// with a struck-through time but stays fully interactive — occupancy is
/// advisory, never a block.
///
/// Once the slot is part of an active order it only gets the green LOOK
/// (background + border) — the numbers stay the ordinary interest/free info,
/// with people already assigned on the order subtracted by the caller; the
/// order's own details live in the "Objednávky" section. Purely
/// presentational — callbacks injected — so it's widget-testable.
class SlotCell extends StatelessWidget {
  const SlotCell({
    super.key,
    required this.time,
    required this.count,
    required this.intensity,
    required this.isOrderable,
    required this.mine,
    this.onTap,
    this.onLongPress,
    this.venueFree,
    this.venueOurs = 0,
    this.ordered = false,
  });

  final HourMinute time;
  final int count;

  /// 0.0–1.0 popularity shading.
  final double intensity;
  final bool isOrderable;
  final bool mine;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Free lanes at the venue (scraped); null = no occupancy info.
  final int? venueFree;

  /// Occupied places at the venue booked by OUR team (scraped); 0 = none.
  final int venueOurs;

  /// The slot is part of an active order — green look, same numbers.
  final bool ordered;

  bool get _scraped => venueFree != null;
  bool get _venueFull => venueFree != null && venueFree! <= 0;

  /// Full only with foreign bookings — the discouraging look. Full-by-us
  /// renders friendly (it's our own reservation waiting for an order), and an
  /// ordered slot is past discouraging by definition.
  bool get _blockedByOthers => _venueFull && venueOurs <= 0 && !ordered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: _blockedByOthers ? 0.55 : 1,
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            // Ordered cells leave the popularity heat scale — their soft
            // green background says "done deal", not "how many can play".
            color: ordered
                ? Color.lerp(
                    scheme.surfaceContainerHighest, Colors.green, 0.18)
                : Color.lerp(
                    scheme.surfaceContainerHighest, scheme.primaryContainer,
                    intensity),
            border: Border.all(
              color: ordered
                  ? Colors.green
                  : _blockedByOthers
                      ? scheme.error
                      : (mine ? scheme.primary : scheme.outlineVariant),
              width: ordered || (mine && !_blockedByOthers) ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                time.display(),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      decoration:
                          _blockedByOthers ? TextDecoration.lineThrough : null,
                    ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isOrderable && !ordered)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(Icons.check_circle,
                          size: 14, color: scheme.primary),
                    ),
                  // Home = our booking at the venue (green tint when the
                  // order exists, primary otherwise).
                  if (venueOurs > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(Icons.home,
                          size: 14,
                          color: ordered ? Colors.green : scheme.primary),
                    ),
                  // Plain team count, or "team/free lanes" when scraped —
                  // the ordered state changes only the colors.
                  Text(
                    _scraped ? '$count/$venueFree' : '$count',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
