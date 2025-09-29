import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balumohol/core/utils/formatting.dart';
import 'package:balumohol/features/geofence/constants.dart';
import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/models/geofence_result.dart';
import 'package:balumohol/features/geofence/models/location_history_entry.dart';
import 'package:balumohol/features/geofence/models/polygon_feature.dart';
import 'package:balumohol/features/geofence/models/position_sample.dart';
import 'package:balumohol/features/geofence/utils/geo_utils.dart';

class GeofenceMapController extends ChangeNotifier {
  GeofenceMapController();

  final MapController mapController = MapController();

  final List<PolygonFeature> _polygons = [];
  final List<PositionSample> _samples = [];
  final List<LocationHistoryEntry> _history = [];
  final List<CustomPlace> _customPlaces = [];

  LatLng? _currentLocation;
  double? _currentAccuracy;
  bool _insideTarget = false;
  String _statusMessage = 'সীমানা লোড হচ্ছে...';
  String? _errorMessage;
  bool _mapReady = false;
  bool _permissionDenied = false;
  bool _hasCenteredOnUser = false;
  bool _initialised = false;

  LatLng _fallbackCenter = const LatLng(23.8103, 90.4125);
  LatLng? _pendingCenter;
  double? _pendingZoom;
  double? _pendingRotation;
  PolygonFeature? _selectedPolygon;
  PolygonFeature? _primaryPolygon;
  PolygonFeature? _dissolvedPolygon;
  LatLng? _primaryCenter;

  SharedPreferences? _prefs;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _historyTimer;

  bool _disposed = false;

  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;
    _prefs = await SharedPreferences.getInstance();
    await _loadGeoJsonBoundary();
    await _loadHistory();
    await _loadCustomPlaces();
    await _startLocationTracking();
    _historyTimer = Timer.periodic(
      historyInterval,
      (_) => _recordHistoryEntry(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _historyTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  List<PolygonFeature> get polygons => List.unmodifiable(_polygons);
  List<LocationHistoryEntry> get history => List.unmodifiable(_history);
  List<CustomPlace> get customPlaces => List.unmodifiable(_customPlaces);

  LatLng? get currentLocation => _currentLocation;
  double? get currentAccuracy => _currentAccuracy;
  bool get insideTarget => _insideTarget;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  bool get permissionDenied => _permissionDenied;
  LatLng get fallbackCenter => _fallbackCenter;
  PolygonFeature? get selectedPolygon => _selectedPolygon;
  PolygonFeature? get dissolvedPolygon => _dissolvedPolygon;
  LatLng? get primaryCenter => _primaryCenter;

  void onMapReady() {
    _mapReady = true;
    if (_pendingCenter != null) {
      mapController.move(_pendingCenter!, _pendingZoom ?? 15);
      _pendingCenter = null;
      _pendingZoom = null;
    }
    if (_pendingRotation != null) {
      mapController.rotate(_pendingRotation!);
      _pendingRotation = null;
    }
  }

  void moveMap(LatLng target, double zoom) {
    if (!_mapReady) {
      _pendingCenter = target;
      _pendingZoom = zoom;
      return;
    }
    mapController.move(target, zoom);
  }

  void resetRotation() {
    if (!_mapReady) {
      _pendingRotation = 0;
      return;
    }
    mapController.rotate(0);
  }

  void centerOnPrimaryArea() {
    if (_primaryPolygon != null) {
      highlightPolygon(_primaryPolygon);
    } else {
      highlightPolygon(null);
    }

    final targetPolygon = _dissolvedPolygon ?? _primaryPolygon;
    if (targetPolygon != null) {
      final bounds = _boundsForPolygon(targetPolygon);
      if (bounds != null) {
        final zoom = _zoomForBounds(bounds);
        moveMap(bounds.center, zoom);
        return;
      }
    }

    if (_primaryCenter != null) {
      moveMap(_primaryCenter!, 16);
      return;
    }

    moveMap(_fallbackCenter, 15);
  }

  Future<void> calibrateNow() async {
    final hasPermission = await _ensurePermission();
    if (!hasPermission) {
      return;
    }

    _statusMessage =
        'ক্যালিব্রেশন চলছে — সামান্য নড়াচড়া করুন এবং জিপিএস স্থিতিশীল হওয়ার জন্য অপেক্ষা করুন...';
    _hasCenteredOnUser = false;
    _errorMessage = null;
    _samples.clear();
    _notifySafely();

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 20),
      );
      _handlePosition(position);
    } catch (e) {
      _errorMessage = 'ক্যালিব্রেশন ব্যর্থ হয়েছে: $e';
      _notifySafely();
    }
  }

  Future<void> addCustomPlace(CustomPlace place) async {
    _customPlaces.add(place);
    _notifySafely();
    await _persistCustomPlaces();
  }

  void highlightPolygon(PolygonFeature? polygon) {
    _selectedPolygon = polygon;
    _notifySafely();
  }

  void focusPolygon(PolygonFeature polygon) {
    highlightPolygon(polygon);
    final bounds = _boundsForPolygon(polygon);
    if (bounds == null) {
      return;
    }
    final targetZoom = _zoomForBounds(bounds);
    moveMap(bounds.center, targetZoom);
  }

  PolygonFeature? polygonAt(LatLng point) {
    for (final polygon in _polygons) {
      if (isPointInsidePolygon(point, polygon)) {
        return polygon;
      }
    }
    return null;
  }

  Future<void> _loadGeoJsonBoundary() async {
    try {
      final raw = await rootBundle.loadString('assets/output.geojson');
      final Map<String, dynamic> data =
          json.decode(raw) as Map<String, dynamic>;
      final polygons = parsePolygons(data);
      final dissolved = dissolvePolygons(polygons);
      final center = computeBoundsCenter(polygons);
      final centralPolygon = _findCentralPolygon(polygons, center);
      final resolvedCenter = dissolved != null
          ? polygonCentroid(dissolved)
          : (centralPolygon != null
              ? polygonCentroid(centralPolygon)
              : center);
      _polygons
        ..clear()
        ..addAll(polygons);
      _selectedPolygon = null;
      _primaryPolygon = centralPolygon;
      _dissolvedPolygon = dissolved;
      _primaryCenter = resolvedCenter ?? center;

      final focusPolygon = _dissolvedPolygon ?? _primaryPolygon;
      if (focusPolygon != null) {
        final bounds = _boundsForPolygon(focusPolygon);
        if (bounds != null) {
          _fallbackCenter = bounds.center;
          _pendingCenter = bounds.center;
          _pendingZoom = _zoomForBounds(bounds);
        }
      }

      if (_pendingCenter == null && _primaryCenter != null) {
        _fallbackCenter = _primaryCenter!;
        _pendingCenter = _primaryCenter;
        _pendingZoom = 16;
      } else if (_pendingCenter == null && center != null) {
        _fallbackCenter = center;
        _pendingCenter = center;
        _pendingZoom = 16;
      }
      _statusMessage = 'জিপিএস সিগন্যালের জন্য অপেক্ষা করা হচ্ছে...';
      _notifySafely();
    } catch (e) {
      _statusMessage = 'কার্যালয়ের সীমানা লোড করা যায়নি।';
      _errorMessage = e.toString();
      _notifySafely();
    }
  }

  Future<void> _loadHistory() async {
    final stored = _prefs?.getString(historyStorageKey);
    if (stored == null) return;
    try {
      final decoded = json.decode(stored) as List<dynamic>;
      final entries = decoded
          .map((e) => LocationHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _history
        ..clear()
        ..addAll(entries);
      _notifySafely();
    } catch (_) {
      // ignore malformed history
    }
  }

  Future<void> _loadCustomPlaces() async {
    final stored = _prefs?.getString(customPlacesStorageKey);
    if (stored == null) return;
    try {
      final decoded = json.decode(stored) as List<dynamic>;
      final places = decoded
          .whereType<Map<String, dynamic>>()
          .map(CustomPlace.fromJson)
          .toList();
      _customPlaces
        ..clear()
        ..addAll(places);
      _notifySafely();
    } catch (_) {
      // ignore malformed stored data
    }
  }

  Future<void> _persistHistory() async {
    final encoded = json.encode(_history.map((e) => e.toJson()).toList());
    await _prefs?.setString(historyStorageKey, encoded);
  }

  Future<void> _persistCustomPlaces() async {
    final encoded =
        json.encode(_customPlaces.map((place) => place.toJson()).toList());
    await _prefs?.setString(customPlacesStorageKey, encoded);
  }

  PolygonFeature? _findCentralPolygon(
    List<PolygonFeature> polygons,
    LatLng? overallCenter,
  ) {
    if (polygons.isEmpty) {
      return null;
    }

    PolygonFeature? candidate;
    double closestDistance = double.infinity;

    if (overallCenter != null) {
      for (final polygon in polygons) {
        if (polygon.outer.isEmpty) continue;
        final centroid = polygonCentroid(polygon);
        if (centroid == null) continue;
        final distance = Geolocator.distanceBetween(
          overallCenter.latitude,
          overallCenter.longitude,
          centroid.latitude,
          centroid.longitude,
        );
        if (distance < closestDistance) {
          closestDistance = distance;
          candidate = polygon;
        }
      }
    }

    candidate ??= polygons.firstWhere(
      (polygon) => polygon.outer.isNotEmpty,
      orElse: () => polygons.first,
    );
    return candidate;
  }

  _PolygonBounds? _boundsForPolygon(PolygonFeature polygon) {
    if (polygon.outer.isEmpty) {
      return null;
    }

    double minLat = polygon.outer.first.latitude;
    double maxLat = polygon.outer.first.latitude;
    double minLng = polygon.outer.first.longitude;
    double maxLng = polygon.outer.first.longitude;

    void updateBounds(LatLng point) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    for (final point in polygon.outer) {
      updateBounds(point);
    }
    for (final hole in polygon.holes) {
      for (final point in hole) {
        updateBounds(point);
      }
    }

    return _PolygonBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  double _zoomForBounds(_PolygonBounds bounds) {
    final latSpan = (bounds.maxLat - bounds.minLat).abs();
    final lngSpan = (bounds.maxLng - bounds.minLng).abs();
    final maxSpan = math.max(latSpan, lngSpan);
    final paddedSpan = math.max(maxSpan * 1.2, 1e-6);
    final zoom = math.log(360 / paddedSpan) / math.log(2);
    return zoom.clamp(5, 18).toDouble();
  }

  Future<void> _recordHistoryEntry() async {
    if (_currentLocation == null || _currentAccuracy == null) return;
    final entry = LocationHistoryEntry(
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
      inside: _insideTarget,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      accuracy: _currentAccuracy!,
    );
    _history.add(entry);
    if (_history.length > maxHistoryEntries) {
      _history.removeRange(0, _history.length - maxHistoryEntries);
    }
    await _persistHistory();
    _notifySafely();
  }

  Future<void> _startLocationTracking() async {
    final hasPermission = await _ensurePermission();
    if (!hasPermission) {
      return;
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _handlePosition,
      onError: (Object error) {
        _errorMessage = error.toString();
        _statusMessage = 'অবস্থান পাওয়ার সময় ত্রুটি ঘটেছে।';
        _notifySafely();
      },
    );
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _statusMessage = 'এই ডিভাইসে অবস্থান সেবা বন্ধ আছে।';
      _errorMessage = 'আপনার অবস্থান অনুসরণ করতে অবস্থান সেবা চালু করুন।';
      _notifySafely();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _permissionDenied = true;
      _statusMessage = 'অবস্থান অনুমতি প্রত্যাখ্যান করা হয়েছে।';
      _errorMessage = 'জিপিএস ট্র্যাকিং চালু রাখতে অবস্থান অনুমতি দিন।';
      _notifySafely();
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _permissionDenied = true;
      _statusMessage = 'অবস্থান অনুমতি স্থায়ীভাবে প্রত্যাখ্যান করা হয়েছে।';
      _errorMessage = 'চালিয়ে যেতে সিস্টেম সেটিংস থেকে অবস্থান অনুমতি সক্রিয় করুন।';
      _notifySafely();
      return false;
    }

    _permissionDenied = false;
    _errorMessage = null;
    if (_statusMessage == 'সীমানা লোড হচ্ছে...') {
      _statusMessage = 'জিপিএস সিগন্যালের জন্য অপেক্ষা করা হচ্ছে...';
    }
    _notifySafely();
    return true;
  }

  void _handlePosition(Position position) {
    final sample = PositionSample(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestampMs:
          position.timestamp?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
    );

    _samples.removeWhere(
      (existing) =>
          sample.timestampMs - existing.timestampMs >
          sampleRetentionDuration.inMilliseconds,
    );
    _samples.add(sample);
    if (_samples.length > sampleBufferSize) {
      _samples.removeRange(0, _samples.length - sampleBufferSize);
    }

    final latest = _samples.last;
    final bestAccuracySample = _samples.reduce(
      (a, b) => a.accuracy <= b.accuracy ? a : b,
    );

    final location = LatLng(latest.latitude, latest.longitude);
    final result = _evaluateGeofence(location);

    _currentLocation = location;
    _currentAccuracy = bestAccuracySample.accuracy;
    _insideTarget = result.inside;
    _statusMessage = result.statusMessage;
    _errorMessage = null;

    if (!_hasCenteredOnUser) {
      _hasCenteredOnUser = true;
      moveMap(location, defaultFollowZoom);
    }

    _notifySafely();
  }

  GeofenceResult _evaluateGeofence(LatLng position) {
    if (_polygons.isEmpty) {
      return const GeofenceResult(
        inside: false,
        statusMessage: 'সীমানার তথ্য পাওয়া যায়নি।',
      );
    }

    bool inside = false;
    double minDistance = double.infinity;

    for (final polygon in _polygons) {
      if (isPointInsidePolygon(position, polygon)) {
        inside = true;
        break;
      }
      minDistance = math.min(
        minDistance,
        distanceToPolygon(position, polygon),
      );
    }

    if (inside) {
      return const GeofenceResult(
        inside: true,
        statusMessage: '✅ আপনি নির্ধারিত এলাকায় আছেন!',
      );
    }

    final distanceText = minDistance.isFinite
        ? formatKilometers(minDistance / 1000)
        : '—';
    return GeofenceResult(
      inside: false,
      statusMessage: '❌ আপনি নির্ধারিত এলাকায় নেই। দূরত্ব: $distanceText।',
    );
  }

  bool _notifySafely() {
    if (_disposed) {
      return false;
    }
    notifyListeners();
    return true;
  }
}

class _PolygonBounds {
  const _PolygonBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  LatLng get center =>
      LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
}
