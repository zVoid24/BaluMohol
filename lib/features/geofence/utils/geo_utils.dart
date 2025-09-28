import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:balumohol/features/geofence/models/polygon_feature.dart';

List<PolygonFeature> parsePolygons(Map<String, dynamic> data) {
  final features = data['features'] as List<dynamic>? ?? [];
  final polygons = <PolygonFeature>[];

  for (int index = 0; index < features.length; index++) {
    final feature = features[index];
    if (feature is! Map<String, dynamic>) continue;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) continue;
    final type = geometry['type'] as String?;
    final coordinates = geometry['coordinates'];
    final properties = <String, dynamic>{};
    final rawProps = feature['properties'];
    if (rawProps is Map) {
      for (final entry in rawProps.entries) {
        properties[entry.key.toString()] = entry.value;
      }
    }

    if (type == 'Polygon' && coordinates is List) {
      polygons.add(
        _polygonFromCoords(
          id: 'feature_$index',
          coordinates: coordinates.cast<List<dynamic>>(),
          properties: properties,
        ),
      );
    } else if (type == 'MultiPolygon' && coordinates is List) {
      for (int polyIndex = 0; polyIndex < coordinates.length; polyIndex++) {
        final polygonCoords = coordinates[polyIndex];
        if (polygonCoords is List) {
          polygons.add(
            _polygonFromCoords(
              id: 'feature_${index}_$polyIndex',
              coordinates: polygonCoords.cast<List<dynamic>>(),
              properties: properties,
            ),
          );
        }
      }
    }
  }

  return polygons;
}

PolygonFeature _polygonFromCoords({
  required String id,
  required List<List<dynamic>> coordinates,
  required Map<String, dynamic> properties,
}) {
  if (coordinates.isEmpty) {
    return PolygonFeature(
      id: id,
      outer: const [],
      holes: const [],
      properties: Map<String, dynamic>.unmodifiable(properties),
    );
  }

  final outer = _latLngListFromRing(coordinates.first);
  final holes = coordinates
      .skip(1)
      .map<List<LatLng>>(_latLngListFromRing)
      .toList(growable: false);
  return PolygonFeature(
    id: id,
    outer: outer,
    holes: holes,
    properties: Map<String, dynamic>.unmodifiable(properties),
  );
}

List<LatLng> _latLngListFromRing(List<dynamic> ring) {
  return ring.map<LatLng>((coord) {
    final List<dynamic> pair = coord as List<dynamic>;
    final lng = (pair[0] as num).toDouble();
    final lat = (pair[1] as num).toDouble();
    return LatLng(lat, lng);
  }).toList();
}

LatLng? computeBoundsCenter(List<PolygonFeature> polygons) {
  double? minLat, maxLat, minLng, maxLng;

  void updateBounds(LatLng point) {
    minLat = (minLat == null)
        ? point.latitude
        : math.min(minLat!, point.latitude);
    maxLat = (maxLat == null)
        ? point.latitude
        : math.max(maxLat!, point.latitude);
    minLng = (minLng == null)
        ? point.longitude
        : math.min(minLng!, point.longitude);
    maxLng = (maxLng == null)
        ? point.longitude
        : math.max(maxLng!, point.longitude);
  }

  for (final polygon in polygons) {
    for (final point in polygon.outer) {
      updateBounds(point);
    }
    for (final hole in polygon.holes) {
      for (final point in hole) {
        updateBounds(point);
      }
    }
  }

  if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
    return null;
  }

  return LatLng((minLat! + maxLat!) / 2, (minLng! + maxLng!) / 2);
}

bool isPointInsidePolygon(LatLng point, PolygonFeature polygon) {
  if (polygon.outer.isEmpty) {
    return false;
  }

  if (!_isPointInsideRing(point, polygon.outer)) {
    return false;
  }

  for (final hole in polygon.holes) {
    if (_isPointInsideRing(point, hole)) {
      return false;
    }
  }
  return true;
}

bool _isPointInsideRing(LatLng point, List<LatLng> ring) {
  bool inside = false;
  for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final double xi = ring[i].longitude;
    final double yi = ring[i].latitude;
    final double xj = ring[j].longitude;
    final double yj = ring[j].latitude;

    final bool intersect =
        ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude <
            (xj - xi) *
                    (point.latitude - yi) /
                    ((yj - yi).abs() < 1e-12 ? 1e-12 : (yj - yi)) +
                xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

double distanceToPolygon(LatLng point, PolygonFeature polygon) {
  double minDistance = double.infinity;

  void processRing(List<LatLng> ring) {
    if (ring.length < 2) return;
    for (int i = 0; i < ring.length; i++) {
      final start = ring[i];
      final end = ring[(i + 1) % ring.length];
      final distance = _distanceToSegment(point, start, end);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
  }

  processRing(polygon.outer);
  for (final hole in polygon.holes) {
    processRing(hole);
  }
  return minDistance;
}

double _distanceToSegment(LatLng point, LatLng start, LatLng end) {
  if (start == end) {
    return Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      start.latitude,
      start.longitude,
    );
  }

  const earthRadius = 6378137.0;
  final originLatRad = point.latitude * math.pi / 180;

  math.Point<double> project(LatLng p) {
    final double x =
        (p.longitude - point.longitude) *
        math.pi /
        180 *
        earthRadius *
        math.cos(originLatRad);
    final double y =
        (p.latitude - point.latitude) * math.pi / 180 * earthRadius;
    return math.Point<double>(x, y);
  }

  final p = math.Point<double>(0, 0);
  final a = project(start);
  final b = project(end);
  final ab = math.Point<double>(b.x - a.x, b.y - a.y);
  final ap = math.Point<double>(p.x - a.x, p.y - a.y);
  final double abLenSq = ab.x * ab.x + ab.y * ab.y;
  double t = 0;
  if (abLenSq > 0) {
    t = (ap.x * ab.x + ap.y * ab.y) / abLenSq;
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
  }

  final closest = math.Point<double>(a.x + ab.x * t, a.y + ab.y * t);
  final dx = p.x - closest.x;
  final dy = p.y - closest.y;
  return math.sqrt(dx * dx + dy * dy);
}
