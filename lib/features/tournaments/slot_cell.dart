import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// One cell of the availability heatmap: start time, player count, shading
/// by popularity, primary border when orderable, check when I ticked it.
/// Purely presentational — callbacks injected — so it's widget-testable.
class SlotCell extends StatelessWidget {
  const SlotCell({
    super.key,
    required this.time,
    required this.count,
    required this.intensity,
    required this.isOrderable,
    required this.mine,
    required this.onTap,
    this.onLongPress,
    this.venueFree,
    this.venueCapacity,
  });

  final HourMinute time;
  final int count;

  /// 0.0–1.0 popularity shading.
  final double intensity;
  final bool isOrderable;
  final bool mine;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Free/total lanes at the venue (scraped); null = no occupancy info.
  final int? venueFree;
  final int? venueCapacity;

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
          padding: const EdgeInsets.symmetric(vertical: 8),
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
                  Text('$count',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              if (venueFree != null)
                Text(
                  _venueFull ? 'plné' : 'volné $venueFree/$venueCapacity',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _venueFull ? scheme.error : scheme.secondary,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
