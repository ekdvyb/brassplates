import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();
final _random = Random.secure();

String newId() => _uuid.v4();

List<int> randomBytes(int length) =>
    List<int>.generate(length, (_) => _random.nextInt(256));

String b64(List<int> bytes) => base64Encode(bytes);
List<int> unb64(String value) => base64Decode(value);

String formatDate(DateTime? date) {
  if (date == null) return '—';
  return DateFormat.yMMMd().format(date.toLocal());
}

String formatDateTime(DateTime? date) {
  if (date == null) return '—';
  return DateFormat.yMMMd().add_Hm().format(date.toLocal());
}

String timeAgo(DateTime? date) {
  if (date == null) return 'Never';
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 30) return '${diff.inDays} d ago';
  return formatDate(date);
}

List<String> parseTags(String csv) => csv
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList(growable: false);

String tagsToCsv(Iterable<String> tags) =>
    tags.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().join(',');

List<String> decodeStringList(String json) {
  try {
    final value = jsonDecode(json);
    if (value is List) return value.map((e) => e.toString()).toList();
  } catch (_) {}
  return const [];
}

String encodeStringList(Iterable<String> values) => jsonEncode(values.toList());

List<Map<String, dynamic>> decodeListOfMaps(String json) {
  try {
    final value = jsonDecode(json);
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
  } catch (_) {}
  return [];
}

Map<String, dynamic> decodeMap(String json) {
  try {
    final value = jsonDecode(json);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  } catch (_) {}
  return <String, dynamic>{};
}

String truncate(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max).trim()}…';

String initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

String plainFromDeltaJson(String json) {
  if (json.trim().isEmpty) return '';
  try {
    final decoded = jsonDecode(json);
    final ops = decoded is Map ? decoded['ops'] : decoded;
    if (ops is! List) return '';
    final buffer = StringBuffer();
    for (final op in ops) {
      if (op is Map && op['insert'] is String) {
        buffer.write(op['insert']);
      }
    }
    return buffer.toString().trim();
  } catch (_) {
    return '';
  }
}

bool isStale(DateTime? lastTested, {int days = 90}) {
  if (lastTested == null) return true;
  return DateTime.now().difference(lastTested).inDays > days;
}

int daysUntil(DateTime? date) {
  if (date == null) return 0;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  return target.difference(today).inDays;
}
