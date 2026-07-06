import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// One cell of the availability heatmap: start time and, below it, how many
/// of our team ticked this slot. When the tournament is scraped, the count
/// reads "team/free" — team members available over free lanes at the venue
/// (team can exceed capacity). Popularity shading and an orderable border
/// round it out. Purely presentational — callbacks injected — so it's
/// widget-testable.
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

  bool get _scraped => venueFree != null;
  bool get _venueFull => venueFree != null && venueFree! <= 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: _venueFull ? 0.55 : 1,
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Color.lerp(
                scheme.surfaceContainerHighest, scheme.primaryContainer,
                intensity),
            border: Border.all(
              color: _venueFull
                  ? scheme.error
                  : (isOrderable ? scheme.primary : scheme.outlineVariant),
              width: isOrderable && !_venueFull ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                time.display(),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      decoration:
                          _venueFull ? TextDecoration.lineThrough : null,
                    ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (mine)
                    const Padding(
                      padding: EdgeInsets.only(right: 2),
                      child: Icon(Icons.check_circle, size: 14),
                    ),
                  // Plain team count, or "team/free lanes" when scraped.
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
