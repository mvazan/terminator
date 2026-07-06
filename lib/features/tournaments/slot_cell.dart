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
  });

  final HourMinute time;
  final int count;

  /// 0.0–1.0 popularity shading.
  final double intensity;
  final bool isOrderable;
  final bool mine;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Color.lerp(
              scheme.surfaceContainerHighest, scheme.primaryContainer,
              intensity),
          border: Border.all(
            color: isOrderable ? scheme.primary : scheme.outlineVariant,
            width: isOrderable ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(time.display(),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (mine)
                  const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Icon(Icons.check_circle, size: 14),
                  ),
                Text('$count', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
