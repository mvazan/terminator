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
/// Once the slot is part of an active order it flips to the "ordered" look:
/// green border, count reads "assigned players/ordered lanes", and the
/// interest-phase markers (check, home, blocked strike-through) drop away.
/// Purely presentational — callbacks injected — so it's widget-testable.
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
    this.orderedLanes = 0,
    this.assigned = 0,
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

  /// Lanes on this slot across the team's active orders; 0 = not ordered.
  final int orderedLanes;

  /// Players already assigned (roster) to this slot; shown with the order.
  final int assigned;

  bool get _scraped => venueFree != null;
  bool get _venueFull => venueFree != null && venueFree! <= 0;
  bool get _ordered => orderedLanes > 0;

  /// Full only with foreign bookings — the discouraging look. Full-by-us
  /// renders friendly (it's our own reservation waiting for an order), and an
  /// ordered slot is past discouraging by definition.
  bool get _blockedByOthers => _venueFull && venueOurs <= 0 && !_ordered;

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
            color: _ordered
                ? Color.lerp(
                    scheme.surfaceContainerHighest, Colors.green, 0.18)
                : Color.lerp(
                    scheme.surfaceContainerHighest, scheme.primaryContainer,
                    intensity),
            border: Border.all(
              color: _ordered
                  ? Colors.green
                  : _blockedByOthers
                      ? scheme.error
                      : (mine ? scheme.primary : scheme.outlineVariant),
              width: _ordered || (mine && !_blockedByOthers) ? 2 : 1,
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
                  if (isOrderable && !_ordered)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(Icons.check_circle,
                          size: 14, color: scheme.primary),
                    ),
                  // Home = ours: primary while it's just our venue booking,
                  // green once ordered — it also flags that the number now
                  // means assigned/lanes instead of interest.
                  if (_ordered || venueOurs > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(Icons.home,
                          size: 14,
                          color: _ordered ? Colors.green : scheme.primary),
                    ),
                  // Ordered: assigned players over ordered lanes. Otherwise
                  // plain team count, or "team/free lanes" when scraped.
                  Text(
                    _ordered
                        ? '$assigned/$orderedLanes'
                        : (_scraped ? '$count/$venueFree' : '$count'),
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
