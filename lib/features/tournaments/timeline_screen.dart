import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/models.dart';
import '../../domain/timeline.dart';
import 'tournament_detail_screen.dart';

const _cellWidth = 84.0;
const _rowHeight = 44.0;
const _labelWidth = 140.0;

/// Bar color for tournaments the viewer hid ("nezajímá mě") when the
/// show-hidden toggle is on.
const _hiddenBarColor = Color(0xFFBDBDBD);

/// Marker line colors: a day with starts vs. a day with an active order.
const _startMarkerColor = Colors.black54;
const _orderedMarkerColor = Color(0xFFD32F2F);

/// Season calendar — the team's spreadsheet as a screen: rows = tournaments,
/// columns = weeks, colored bars = duration. Overlaps at a glance.
/// Vertical lines inside a bar mark days with starts (dark) and days with an
/// active order (red). Display only by design (no trip suggestions).
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  /// Also show my-hidden tournaments (in gray). Off by default.
  bool _showHidden = false;

  @override
  Widget build(BuildContext context) {
    final myHidden =
        ref.watch(myHiddenTournamentsProvider).value ?? const <String>{};
    final tournaments = (ref.watch(allTournamentsProvider).value ?? const [])
        .where((t) =>
            !t.isHidden &&
            !t.isArchived &&
            (_showHidden || !myHidden.contains(t.id)))
        .toList(); // stream is already sorted by startsOn
    final venueNames = ref.watch(venueNamesProvider);

    // Days with starts, and days with an active order, per tournament.
    final slots = ref.watch(slotsProvider).value ?? const <Slot>[];
    final slotById = {for (final s in slots) s.id: s};
    final startDays = <String, Set<Day>>{};
    for (final s in slots) {
      startDays.putIfAbsent(s.tournamentId, () => {}).add(s.date);
    }
    final orderSlots = ref.watch(orderSlotsProvider).value ??
        const <String, Map<String, int>>{};
    final orderedDays = <String, Set<Day>>{};
    for (final order in ref.watch(ordersProvider).value ?? const <Order>[]) {
      if (!order.isActive) continue;
      for (final slotId
          in (orderSlots[order.id] ?? const <String, int>{}).keys) {
        final slot = slotById[slotId];
        if (slot != null) {
          orderedDays.putIfAbsent(order.tournamentId, () => {}).add(slot.date);
        }
      }
    }

    final timeline = Timeline.build(
      tournaments,
      startDaysByTournament: startDays,
      orderedDaysByTournament: orderedDays,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sezónní kalendář'),
        actions: [
          IconButton(
            tooltip: _showHidden
                ? 'Nezobrazovat skryté turnaje'
                : 'Zobrazit i skryté turnaje (šedě)',
            icon: Icon(_showHidden
                ? Icons.visibility
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _showHidden = !_showHidden),
          ),
        ],
      ),
      body: timeline.isEmpty
          ? const Center(child: Text('Žádné turnaje k zobrazení.'))
          : SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: _labelWidth),
                        for (final col in timeline.columns)
                          SizedBox(
                            width: _cellWidth,
                            child: Text(
                              col.label(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ..._buildRows(timeline, myHidden, venueNames),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _buildRows(Timeline timeline, Set<String> myHidden,
      Map<String, String> venueNames) {
    // Palette indexes count visible rows only, so existing tournaments keep
    // their colors when a gray (hidden) row interleaves.
    var paletteIndex = 0;
    return [
      for (final row in timeline.rows)
        _TimelineRow(
          row: row,
          venueName: venueNames[row.tournament.venueId] ?? '?',
          columnCount: timeline.columns.length,
          hidden: myHidden.contains(row.tournament.id),
          color: myHidden.contains(row.tournament.id)
              ? _hiddenBarColor
              : _barColors[paletteIndex++ % _barColors.length],
        ),
    ];
  }
}

const _barColors = [
  Color(0xFF8BC34A),
  Color(0xFFFFEB3B),
  Color(0xFF90CAF9),
  Color(0xFFFFAB91),
  Color(0xFFCE93D8),
  Color(0xFF80CBC4),
];

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.row,
    required this.venueName,
    required this.columnCount,
    required this.color,
    this.hidden = false,
  });

  final TimelineRow row;
  final String venueName;
  final int columnCount;
  final Color color;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              TournamentDetailScreen(tournamentId: row.tournament.id),
        ),
      ),
      child: SizedBox(
        height: _rowHeight,
        child: Row(
          children: [
            SizedBox(
              width: _labelWidth,
              child: Text(
                row.tournament.timelineLabel(venueName),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: hidden
                          ? Theme.of(context).colorScheme.outline
                          : null,
                    ),
              ),
            ),
            for (var col = 0; col < columnCount; col++)
              Container(
                width: _cellWidth,
                height: _rowHeight - 10,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).dividerColor, width: 0.4),
                ),
                // The bar fills only the days the tournament actually spans
                // (a Fri–Sun tournament colors the right 3/7 of its week);
                // vertical lines mark days with starts / an active order.
                child: Stack(
                  children: [
                    if (row.fillFrom(col) > 0)
                      Positioned(
                        left: row.insetAt(col) * _cellWidth,
                        width: row.fillFrom(col) * _cellWidth,
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(color: color),
                      ),
                    for (final m in row.markersIn(col))
                      Positioned(
                        // Centered within the day's seventh, 2 px wide.
                        left: (m.dayIndex + 0.5) / 7 * _cellWidth - 1,
                        width: 2,
                        top: 2,
                        bottom: 2,
                        child: ColoredBox(
                          color: m.kind == DayMarkerKind.ordered
                              ? _orderedMarkerColor
                              : _startMarkerColor,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
