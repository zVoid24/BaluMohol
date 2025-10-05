import 'dart:ui';

import 'package:latlong2/latlong.dart';

class UserPolygon {
  const UserPolygon({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.points,
    this.fields = const [],
  });

  factory UserPolygon.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? const [];
    final points = rawPoints
        .whereType<Map<String, dynamic>>()
        .map(
          (point) => LatLng(
            (point['lat'] as num?)?.toDouble() ?? 0,
            (point['lng'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();

    final rawFields = json['fields'] as List<dynamic>? ?? const [];
    final fields = rawFields
        .whereType<Map<String, dynamic>>()
        .map(UserPolygonField.fromJson)
        .toList();

    return UserPolygon(
      id: (json['id'] as String? ?? '').trim().isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : (json['id'] as String).trim(),
      name: (json['name'] as String? ?? '').trim(),
      colorValue: (json['color'] as num?)?.toInt() ?? _defaultColorValue,
      points: points,
      fields: fields,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': colorValue,
      'points': points
          .map(
            (point) => {
              'lat': point.latitude,
              'lng': point.longitude,
            },
          )
          .toList(),
      'fields': fields.map((field) => field.toJson()).toList(),
    };
  }

  Color get color => Color(colorValue);

  final String id;
  final String name;
  final int colorValue;
  final List<LatLng> points;
  final List<UserPolygonField> fields;
}

const int _defaultColorValue = 0xFF1976D2;

enum UserPolygonFieldType { text, number, date }

class UserPolygonField {
  const UserPolygonField({
    required this.name,
    required this.type,
    this.value,
  });

  factory UserPolygonField.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String?)?.toLowerCase();
    final type = _fieldTypeFromString(rawType);
    final rawValue = json['value'];
    return UserPolygonField(
      name: (json['name'] as String? ?? '').trim(),
      type: type,
      value: _normalizeStoredValue(type, rawValue),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'value': switch (type) {
        UserPolygonFieldType.date => _dateValue?.toIso8601String() ?? value,
        _ => value,
      },
    };
  }

  String get propertyKey {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  bool get hasContent {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }

  dynamic get propertyValue {
    switch (type) {
      case UserPolygonFieldType.text:
        final text = value?.toString().trim();
        return text ?? '';
      case UserPolygonFieldType.number:
        if (value is num) {
          return value;
        }
        if (value is String) {
          final parsed = num.tryParse(value);
          return parsed ?? value;
        }
        return value;
      case UserPolygonFieldType.date:
        final date = _dateValue;
        if (date != null) {
          return _formatDate(date);
        }
        if (value is String) {
          final parsed = DateTime.tryParse(value);
          return parsed != null ? _formatDate(parsed) : value;
        }
        return value?.toString() ?? '';
    }
  }

  DateTime? get _dateValue {
    if (value is DateTime) {
      return value as DateTime;
    }
    if (value is String) {
      return DateTime.tryParse(value as String);
    }
    return null;
  }

  static UserPolygonFieldType _fieldTypeFromString(String? raw) {
    switch (raw) {
      case 'number':
        return UserPolygonFieldType.number;
      case 'date':
        return UserPolygonFieldType.date;
      case 'text':
      default:
        return UserPolygonFieldType.text;
    }
  }

  static dynamic _normalizeStoredValue(
    UserPolygonFieldType type,
    dynamic raw,
  ) {
    switch (type) {
      case UserPolygonFieldType.text:
        return raw?.toString() ?? '';
      case UserPolygonFieldType.number:
        if (raw is num) {
          return raw;
        }
        if (raw is String) {
          final parsed = num.tryParse(raw);
          return parsed ?? raw;
        }
        return raw;
      case UserPolygonFieldType.date:
        if (raw is DateTime) {
          return raw;
        }
        if (raw is String) {
          final parsed = DateTime.tryParse(raw);
          return parsed ?? raw;
        }
        return raw;
    }
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  final String name;
  final UserPolygonFieldType type;
  final dynamic value;
}
