import 'dart:ui';

import 'package:latlong2/latlong.dart';

class UserPolygon {
  const UserPolygon({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.points,
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

    return UserPolygon(
      id: (json['id'] as String? ?? '').trim().isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : (json['id'] as String).trim(),
      name: (json['name'] as String? ?? '').trim(),
      colorValue: (json['color'] as num?)?.toInt() ?? _defaultColorValue,
      points: points,
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
    };
  }

  Color get color => Color(colorValue);

  final String id;
  final String name;
  final int colorValue;
  final List<LatLng> points;
}

const int _defaultColorValue = 0xFF1976D2;
