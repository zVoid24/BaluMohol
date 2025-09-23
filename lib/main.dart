import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

const int _sampleBufferSize = 8;
const Duration _historyInterval = Duration(seconds: 10);
const int _maxHistoryEntries = 200;
const String _historyStorageKey = 'locationHistory';
const Duration _sampleRetentionDuration = Duration(seconds: 12);
const double _defaultFollowZoom = 17;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo-fenced Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const GeofenceMapPage(),
    );
  }
}

class GeofenceMapPage extends StatefulWidget {
  const GeofenceMapPage({super.key});

  @override
  State<GeofenceMapPage> createState() => _GeofenceMapPageState();
}

class _GeofenceMapPageState extends State<GeofenceMapPage> {
  final MapController _mapController = MapController();
  final List<_PolygonFeature> _polygons = [];
  final List<_PositionSample> _samples = [];
  final List<LocationHistoryEntry> _history = [];

  LatLng? _currentLocation;
  double? _currentAccuracy;
  bool _insideTarget = false;
  String _statusMessage = 'Loading boundary...';
  String? _errorMessage;

  SharedPreferences? _prefs;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _historyTimer;

  bool _mapReady = false;
  bool _permissionDenied = false;
  bool _hasCenteredOnUser = false;

  LatLng _fallbackCenter = const LatLng(23.8103, 90.4125);
  LatLng? _pendingCenter;
  double? _pendingZoom;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadGeoJsonBoundary();
    await _loadHistory();
    await _startLocationTracking();
    _historyTimer = Timer.periodic(
      _historyInterval,
      (_) => _recordHistoryEntry(),
    );
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadGeoJsonBoundary() async {
    try {
      final raw = await rootBundle.loadString('assets/output.geojson');
      print(raw);
      final Map<String, dynamic> data =
          json.decode(raw) as Map<String, dynamic>;
      final polygons = _parsePolygons(data);
      final center = _computeBoundsCenter(polygons);
      if (!mounted) return;
      setState(() {
        _polygons
          ..clear()
          ..addAll(polygons);
        if (center != null) {
          _fallbackCenter = center;
        }
        _statusMessage = 'Waiting for GPS fix...';
      });
      if (center != null) {
        _moveMap(center, 16);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Failed to load office boundary.';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadHistory() async {
    if (_prefs == null) return;
    final stored = _prefs!.getString(_historyStorageKey);
    if (stored == null) return;
    try {
      final decoded = json.decode(stored) as List<dynamic>;
      final entries = decoded
          .map((e) => LocationHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(entries);
      });
    } catch (e) {
      // ignore malformed history
    }
  }

  Future<void> _persistHistory() async {
    if (_prefs == null) return;
    final encoded = json.encode(_history.map((e) => e.toJson()).toList());
    await _prefs!.setString(_historyStorageKey, encoded);
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
    if (!mounted) return;
    setState(() {
      _history.add(entry);
      if (_history.length > _maxHistoryEntries) {
        _history.removeRange(0, _history.length - _maxHistoryEntries);
      }
    });
    await _persistHistory();
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
          (position) {
            _handlePosition(position);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _errorMessage = error.toString();
              _statusMessage = 'Error obtaining location.';
            });
          },
        );
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      setState(() {
        _statusMessage = 'Location services are disabled on this device.';
        _errorMessage = 'Enable location services to track your position.';
      });
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return false;
      setState(() {
        _permissionDenied = true;
        _statusMessage = 'Location permission denied.';
        _errorMessage = 'Grant location access to enable GPS tracking.';
      });
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      setState(() {
        _permissionDenied = true;
        _statusMessage = 'Location permission permanently denied.';
        _errorMessage =
            'Please enable location permissions from system settings to continue.';
      });
      return false;
    }

    if (!mounted) return true;
    setState(() {
      _permissionDenied = false;
      _errorMessage = null;
      if (_statusMessage == 'Loading boundary...') {
        _statusMessage = 'Waiting for GPS fix...';
      }
    });
    return true;
  }

  void _handlePosition(Position position) {
    final sample = _PositionSample(
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
          _sampleRetentionDuration.inMilliseconds,
    );
    _samples.add(sample);
    if (_samples.length > _sampleBufferSize) {
      _samples.removeRange(0, _samples.length - _sampleBufferSize);
    }

    final latest = _samples.last;
    final bestAccuracySample = _samples.reduce(
      (a, b) => a.accuracy <= b.accuracy ? a : b,
    );

    final location = LatLng(latest.latitude, latest.longitude);
    final result = _evaluateGeofence(location);

    if (!mounted) return;
    setState(() {
      _currentLocation = location;
      _currentAccuracy = bestAccuracySample.accuracy;
      _insideTarget = result.inside;
      _statusMessage = result.statusMessage;
      _errorMessage = null;
    });

    if (!_hasCenteredOnUser) {
      _hasCenteredOnUser = true;
      _moveMap(location, _defaultFollowZoom);
    }
  }

  _GeofenceResult _evaluateGeofence(LatLng position) {
    if (_polygons.isEmpty) {
      return const _GeofenceResult(
        inside: false,
        statusMessage: 'Boundary not available.',
      );
    }

    bool inside = false;
    double minDistance = double.infinity;

    for (final polygon in _polygons) {
      if (_isPointInsidePolygon(position, polygon)) {
        inside = true;
        break;
      }
      minDistance = math.min(
        minDistance,
        _distanceToPolygon(position, polygon),
      );
    }

    if (inside) {
      return const _GeofenceResult(
        inside: true,
        statusMessage: '✅ You are inside the target area!',
      );
    }

    final distanceKm = minDistance.isFinite
        ? (minDistance / 1000).toStringAsFixed(2)
        : '—';
    return _GeofenceResult(
      inside: false,
      statusMessage:
          '❌আপনি লক্ষ্য/টার্গেট এলাকার বাইরে আছেন। দূরত্ব: $distanceKm কি.মি.',
    );
  }

  Future<void> _calibrateNow() async {
    final hasPermission = await _ensurePermission();
    if (!hasPermission) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _statusMessage =
          'Calibrating — move a little and allow GPS to warm up...';
      _hasCenteredOnUser = false;
    });

    _samples.clear();
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 20),
      );
      _handlePosition(position);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Calibration failed: $e';
      });
    }
  }

  void _moveMap(LatLng target, double zoom) {
    if (!_mapReady) {
      _pendingCenter = target;
      _pendingZoom = zoom;
      return;
    }
    _mapController.move(target, zoom);
  }

  List<Polygon> _buildPolygons() {
    final Color borderColor = Colors.blue.shade600;
    final Color fillColor = const Color(0xFF42A5F5).withOpacity(0.2);

    return _polygons
        .where((polygon) => polygon.outer.isNotEmpty)
        .map(
          (polygon) => Polygon(
            points: polygon.outer,
            holePointsList: polygon.holes,
            color: fillColor,
            borderColor: borderColor,
            borderStrokeWidth: 2.8,
            isFilled: true,
          ),
        )
        .toList();
  }

  Marker? _buildCurrentLocationMarker() {
    if (_currentLocation == null) {
      return null;
    }
    final accuracyText = _currentAccuracy != null
        ? '${_currentAccuracy!.round()} m'
        : '—';
    return Marker(
      point: _currentLocation!,
      width: 48,
      height: 48,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: _onCurrentLocationMarkerTap,
        child: Tooltip(
          message: 'You are here\nAccuracy: $accuracyText',
          child: const _CurrentLocationIndicator(),
        ),
      ),
    );
  }

  List<Marker> _buildHistoryMarkers() {
    if (_history.isEmpty) {
      return const [];
    }

    return _history
        .map(
          (entry) => Marker(
            point: LatLng(entry.latitude, entry.longitude),
            width: 20,
            height: 20,
            child: GestureDetector(
              onTap: () => _onHistoryMarkerTap(entry),
              child: Tooltip(
                message:
                    'Time: ${DateTime.fromMillisecondsSinceEpoch(entry.timestampMs).toLocal()}\nInside: ${entry.inside}\nAccuracy: ${entry.accuracy.round()} m',
                child: Container(
                  decoration: BoxDecoration(
                    color: entry.inside ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  void _onCurrentLocationMarkerTap() {
    final location = _currentLocation;
    if (location == null) {
      return;
    }
    final accuracyText = _currentAccuracy != null
        ? '${_currentAccuracy!.toStringAsFixed(1)} m'
        : 'Unavailable';
    final insideText = _insideTarget
        ? 'Inside the target area'
        : 'Outside the target area';
    _showMarkerDetails(
      title: 'Your location',
      content: [
        Text('Latitude: ${location.latitude.toStringAsFixed(6)}'),
        Text('Longitude: ${location.longitude.toStringAsFixed(6)}'),
        Text('Accuracy: $accuracyText'),
        Text(insideText),
        const SizedBox(height: 8),
        Text(_statusMessage),
      ],
    );
  }

  void _onHistoryMarkerTap(LocationHistoryEntry entry) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      entry.timestampMs,
    ).toLocal().toString();
    final insideText = entry.inside ? 'Yes' : 'No';
    _showMarkerDetails(
      title: 'Recorded location',
      content: [
        Text('Latitude: ${entry.latitude.toStringAsFixed(6)}'),
        Text('Longitude: ${entry.longitude.toStringAsFixed(6)}'),
        Text('Accuracy: ${entry.accuracy.toStringAsFixed(1)} m'),
        Text('Inside boundary: $insideText'),
        Text('Time: $timestamp'),
      ],
    );
  }

  void _showMarkerDetails({
    required String title,
    required List<Widget> content,
  }) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard() {
    final accuracyText = _currentAccuracy != null
        ? '${_currentAccuracy!.round()} m'
        : 'waiting...';

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white.withOpacity(0.95),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'জিপিএস এর অবস্থা:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text('সঠিকতা: $accuracyText'),
              const SizedBox(height: 4),
              Text(_statusMessage),
              if (_errorMessage != null) ...[
                const SizedBox(height: 6),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _goToCurrentLocation() {
    final location = _currentLocation;
    if (location != null) {
      _moveMap(location, _defaultFollowZoom);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Current location not available yet.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMarker = _buildCurrentLocationMarker();
    final historyMarkers = _buildHistoryMarkers();

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'current_location_btn',
              onPressed: _goToCurrentLocation,
              tooltip: 'Go to current location',
              child: const Icon(Icons.my_location),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'calibrate_btn',
              onPressed: _permissionDenied ? null : _calibrateNow,
              label: const Text('Calibrate now'),
              icon: const Icon(Icons.compass_calibration),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: 15,
              onMapReady: () {
                _mapReady = true;
                if (_pendingCenter != null) {
                  _mapController.move(_pendingCenter!, _pendingZoom ?? 15);
                  _pendingCenter = null;
                  _pendingZoom = null;
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.balumohol',
              ),
              if (_polygons.isNotEmpty)
                PolygonLayer(polygons: _buildPolygons()),
              if (historyMarkers.isNotEmpty)
                MarkerLayer(markers: historyMarkers),
              if (currentMarker != null) MarkerLayer(markers: [currentMarker]),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildStatusCard(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentLocationIndicator extends StatelessWidget {
  const _CurrentLocationIndicator();

  @override
  Widget build(BuildContext context) {
    final Color haloColor = Colors.blueAccent.shade200;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: haloColor.withOpacity(0.2),
          ),
        ),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blueAccent,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _PositionSample {
  const _PositionSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestampMs,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final int timestampMs;
}

class _PolygonFeature {
  const _PolygonFeature({required this.outer, required this.holes});

  final List<LatLng> outer;
  final List<List<LatLng>> holes;
}

class LocationHistoryEntry {
  const LocationHistoryEntry({
    required this.latitude,
    required this.longitude,
    required this.inside,
    required this.timestampMs,
    required this.accuracy,
  });

  factory LocationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LocationHistoryEntry(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      inside: json['inside'] as bool,
      timestampMs: json['timestamp'] as int,
      accuracy: (json['accuracy'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': latitude,
      'lng': longitude,
      'inside': inside,
      'timestamp': timestampMs,
      'accuracy': accuracy,
    };
  }

  final double latitude;
  final double longitude;
  final bool inside;
  final int timestampMs;
  final double accuracy;
}

class _GeofenceResult {
  const _GeofenceResult({required this.inside, required this.statusMessage});

  final bool inside;
  final String statusMessage;
}

List<_PolygonFeature> _parsePolygons(Map<String, dynamic> data) {
  final features = data['features'] as List<dynamic>? ?? [];
  final polygons = <_PolygonFeature>[];

  for (final feature in features) {
    final geometry =
        (feature as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
    if (geometry == null) continue;
    final type = geometry['type'] as String?;
    final coordinates = geometry['coordinates'];

    if (type == 'Polygon' && coordinates is List) {
      polygons.add(_polygonFromCoords(coordinates.cast<List<dynamic>>()));
    } else if (type == 'MultiPolygon' && coordinates is List) {
      for (final polygonCoords in coordinates) {
        if (polygonCoords is List) {
          polygons.add(_polygonFromCoords(polygonCoords.cast<List<dynamic>>()));
        }
      }
    }
  }

  return polygons;
}

_PolygonFeature _polygonFromCoords(List<List<dynamic>> coordinates) {
  if (coordinates.isEmpty) {
    return const _PolygonFeature(outer: [], holes: []);
  }

  final outer = _latLngListFromRing(coordinates.first);
  final holes = coordinates.skip(1).map(_latLngListFromRing).toList();
  return _PolygonFeature(outer: outer, holes: holes);
}

List<LatLng> _latLngListFromRing(List<dynamic> ring) {
  return ring.map<LatLng>((coord) {
    final List<dynamic> pair = coord as List<dynamic>;
    final lng = (pair[0] as num).toDouble();
    final lat = (pair[1] as num).toDouble();
    return LatLng(lat, lng);
  }).toList();
}

LatLng? _computeBoundsCenter(List<_PolygonFeature> polygons) {
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

bool _isPointInsidePolygon(LatLng point, _PolygonFeature polygon) {
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

double _distanceToPolygon(LatLng point, _PolygonFeature polygon) {
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
