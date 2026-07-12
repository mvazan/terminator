/// Address → coordinates via OSM Nominatim. Free, no API key; the usage
/// policy requires an identifying User-Agent and at most ~1 request/second,
/// which the module-level throttle below enforces process-wide.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

/// Resolves [address] to coordinates, or null when unknown/unreachable.
/// Never throws — a venue without a pin is fine, the map just skips it.
Future<({double lat, double lng})?> geocodeAddress(String address) async {
  final query = address.trim();
  if (query.isEmpty) return null;

  // Nominatim policy: max 1 req/s. Serialize and space out calls.
  final sinceLast = DateTime.now().difference(_lastCall);
  const minGap = Duration(milliseconds: 1100);
  if (sinceLast < minGap) {
    await Future<void>.delayed(minGap - sinceLast);
  }
  _lastCall = DateTime.now();

  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '1',
    });
    final response = await http.get(uri, headers: {
      'User-Agent': 'Terminator/1.x (kuzelky team app)',
    }).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final results = jsonDecode(response.body) as List;
    if (results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    final lat = double.tryParse(first['lat'] as String? ?? '');
    final lng = double.tryParse(first['lon'] as String? ?? '');
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  } catch (e) {
    debugPrint('geocode failed for "$query": $e');
    return null;
  }
}
