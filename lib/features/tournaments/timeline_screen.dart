import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/timeline.dart';
import 'tournament_detail_screen.dart';

const _cellWidth = 84.0;
const _rowHeight = 44.0;
const _labelWidth = 140.0;

/// Season calendar — the team's spreadsheet as a screen: rows = tournaments,
/// columns = weeks, colored bars = duration. Overlaps at a glance.
/// Display only by design (no trip suggestions).
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = (ref.watch(tournamentsProvider).value ?? const [])
        .where((t) => !t.isArchived)
        .toList();
    final venueNames = ref.watch(venueNamesProvider);
    final timeline = Timeline.build(tournaments);

    return Scaffold(
      appBar: AppBar(title: const Text('Sezónní kalendář')),
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
                    for (final (i, row) in timeline.rows.indexed)
                      _TimelineRow(
                        row: row,
                        venueName: venueNames[row.tournament.venueId] ?? '?',
                        columnCount: timeline.columns.length,
                        color: _barColors[i % _barColors.length],
                      ),
                  ],
                ),
              ),
            ),
    );
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
  });

  final TimelineRow row;
  final String venueName;
  final int columnCount;
  final Color color;

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
                style: Theme.of(context).textTheme.bodySmall,
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
                // Fill only the part of the cell the tournament actually spans:
                // a Fri–Sun tournament colors the right 3/7 of its week cell.
                // The three flex weights (×1000 to stay integer) are the left
                // gap, the colored span, and the trailing gap within the week.
                child: row.fillFrom(col) == 0
                    ? null
                    : Row(
                        children: [
                          Expanded(
                            flex: (row.insetAt(col) * 1000).round(),
                            child: const SizedBox(),
                          ),
                          Expanded(
                            flex: (row.fillFrom(col) * 1000).round(),
                            child: ColoredBox(color: color),
                          ),
                          Expanded(
                            flex: ((1 - row.insetAt(col) - row.fillFrom(col)) *
                                    1000)
                                .round(),
                            child: const SizedBox(),
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
