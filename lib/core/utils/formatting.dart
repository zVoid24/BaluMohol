import 'package:latlong2/latlong.dart';

import 'package:balumohol/features/geofence/constants.dart';
import 'package:balumohol/features/geofence/models/polygon_feature.dart';

import 'string_extensions.dart';

const _banglaDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

String toBanglaDigits(String value) {
  final buffer = StringBuffer();
  for (final codeUnit in value.codeUnits) {
    if (codeUnit >= 48 && codeUnit <= 57) {
      buffer.write(_banglaDigits[codeUnit - 48]);
    } else {
      buffer.write(String.fromCharCode(codeUnit));
    }
  }
  return buffer.toString();
}

String _trimTrailingZeros(String value) {
  var result = value;
  if (!result.contains('.')) {
    return result;
  }
  while (result.endsWith('0')) {
    result = result.substring(0, result.length - 1);
  }
  if (result.endsWith('.')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String formatNumber(
  num value, {
  int fractionDigits = 0,
  bool useBanglaDigits = true,
}) {
  String text;
  if (fractionDigits <= 0) {
    text = value.round().toString();
  } else {
    text = _trimTrailingZeros(value.toStringAsFixed(fractionDigits));
  }
  return useBanglaDigits ? toBanglaDigits(text) : text;
}

String formatMeters(
  num value, {
  int fractionDigits = 0,
  bool useBanglaDigits = true,
  String? unitLabel,
}) {
  final resolvedUnit = unitLabel ?? (useBanglaDigits ? 'মিটার' : 'meters');
  return '${formatNumber(value, fractionDigits: fractionDigits, useBanglaDigits: useBanglaDigits)} $resolvedUnit';
}

String formatKilometers(
  double value, {
  int fractionDigits = 2,
  bool useBanglaDigits = true,
  String? unitLabel,
}) {
  final resolvedUnit = unitLabel ?? (useBanglaDigits ? 'কিমি' : 'km');
  return '${formatNumber(value, fractionDigits: fractionDigits, useBanglaDigits: useBanglaDigits)} $resolvedUnit';
}

String formatCoordinate(double value, {bool useBanglaDigits = true}) {
  return formatNumber(
    value,
    fractionDigits: 6,
    useBanglaDigits: useBanglaDigits,
  );
}

String formatLatLng(
  LatLng point, {
  int fractionDigits = 6,
  bool useBanglaDigits = true,
}) {
  final latText = formatNumber(
    point.latitude,
    fractionDigits: fractionDigits,
    useBanglaDigits: useBanglaDigits,
  );
  final lngText = formatNumber(
    point.longitude,
    fractionDigits: fractionDigits,
    useBanglaDigits: useBanglaDigits,
  );
  return '$latText, $lngText';
}

String formatTimestampBangla(int timestampMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
  final year = dt.year.toString().padLeft(4, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final second = dt.second.toString().padLeft(2, '0');
  return toBanglaDigits('$year-$month-$day $hour:$minute:$second');
}

String formatTimestampEnglish(int timestampMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
  final year = dt.year.toString().padLeft(4, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final second = dt.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

List<MapEntry<String, String>> polygonReadableProperties(
  PolygonFeature polygon, {
  bool useBanglaDigits = true,
  String? notAvailableLabel,
}) {
  final props = polygon.properties;
  final seen = <String>{};
  final ordered = <MapEntry<String, dynamic>>[];

  for (final key in preferredPropertyOrder) {
    if (props.containsKey(key)) {
      ordered.add(MapEntry(key, props[key]));
      seen.add(key);
    }
  }

  for (final entry in props.entries) {
    if (seen.contains(entry.key)) continue;
    ordered.add(MapEntry(entry.key, entry.value));
  }

  return ordered
      .where((entry) => !isNullOrEmpty(entry.value))
      .map(
        (entry) => MapEntry(
          prettifyPropertyKey(entry.key),
          formatPropertyValue(
            entry.value,
            useBanglaDigits: useBanglaDigits,
            notAvailableLabel: notAvailableLabel,
          ),
        ),
      )
      .toList();
}

bool isNullOrEmpty(dynamic value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable || value is Map) return value.isEmpty;
  return false;
}

String prettifyPropertyKey(String key) {
  final cleaned = key.replaceAll('_', ' ').trim();
  if (cleaned.isEmpty) {
    return key;
  }

  final words = cleaned.split(RegExp(r'\s+'));
  return words
      .map((word) {
        if (word.isEmpty) return word;
        final hasLower = word.contains(RegExp(r'[a-z]'));
        final hasUpper = word.contains(RegExp(r'[A-Z]'));
        if (hasUpper && !hasLower) {
          return word;
        }
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      })
      .join(' ');
}

String formatPropertyValue(
  dynamic value, {
  bool useBanglaDigits = true,
  String? notAvailableLabel,
}) {
  final unavailable =
      notAvailableLabel ?? (useBanglaDigits ? 'উপলব্ধ নয়' : 'Not available');
  if (value == null) {
    return unavailable;
  }
  if (value is int) {
    return formatNumber(
      value,
      fractionDigits: 0,
      useBanglaDigits: useBanglaDigits,
    );
  }
  if (value is double) {
    final fractionDigits = (value - value.roundToDouble()).abs() < 1e-6 ? 0 : 2;
    return formatNumber(
      value,
      fractionDigits: fractionDigits,
      useBanglaDigits: useBanglaDigits,
    );
  }
  if (value is num) {
    return formatNumber(
      value,
      fractionDigits: 2,
      useBanglaDigits: useBanglaDigits,
    );
  }
  if (value is String) {
    final trimmed = value.trim();
    return useBanglaDigits ? toBanglaDigits(trimmed) : trimmed;
  }
  return value.toString();
}

String formatTimestampLocalized(
  int timestampMs, {
  required bool useBanglaDigits,
}) {
  return useBanglaDigits
      ? formatTimestampBangla(timestampMs)
      : formatTimestampEnglish(timestampMs);
}
