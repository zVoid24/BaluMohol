import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

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
const String _customPlacesStorageKey = 'customPlaces';

const List<String> _placeCategories = [
  'Restaurant',
  'Cafe',
  'Coffee shop',
  'Bakery',
  'Fast food restaurant',
  'Grocery store',
  'Supermarket',
  'Convenience store',
  'Clothing store',
  'Electronics store',
  'Pharmacy',
  'Hospital',
  'Clinic',
  'School',
  'College',
  'University',
  'Library',
  'Hotel',
  'Guest house',
  'ATM',
  'Bank',
  'Fuel station',
  'Car repair',
  'Parking',
  'Park',
  'Playground',
  'Gym',
  'Stadium',
  'Movie theater',
  'Shopping mall',
  'Hardware store',
  'Home goods store',
  'Furniture store',
  'Jewelry store',
  'Salon',
  'Spa',
  'Barbershop',
  'Mosque',
  'Temple',
  'Church',
  'Government office',
  'Police station',
  'Post office',
  'Courier service',
  'Bus station',
  'Train station',
  'Airport',
  'Tourist attraction',
  'Museum',
  'Zoo',
  'Factory',
  'Warehouse',
  'Farm',
  'Water treatment plant',
  'Construction site',
  'Community center',
  'Event venue',
  'Coworking space',
  'Technology park',
  'Religious institution',
  'Sports club',
  'Medical store',
  'Diagnostic center',
  'Pet store',
  'Veterinary clinic',
];

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'জিওফেন্স মানচিত্র',
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
  final List<_CustomPlace> _customPlaces = [];

  LatLng? _currentLocation;
  double? _currentAccuracy;
  bool _insideTarget = false;
  String _statusMessage = 'সীমানা লোড হচ্ছে...';
  String? _errorMessage;

  SharedPreferences? _prefs;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _historyTimer;

  bool _mapReady = false;
  bool _permissionDenied = false;
  bool _hasCenteredOnUser = false;
  bool _skipNextMapTapClear = false;

  LatLng _fallbackCenter = const LatLng(23.8103, 90.4125);
  LatLng? _pendingCenter;
  double? _pendingZoom;
  _PolygonFeature? _selectedPolygon;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadGeoJsonBoundary();
    await _loadHistory();
    await _loadCustomPlaces();
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
      final Map<String, dynamic> data =
          json.decode(raw) as Map<String, dynamic>;
      final polygons = _parsePolygons(data);
      final center = _computeBoundsCenter(polygons);
      if (!mounted) return;
      setState(() {
        _polygons
          ..clear()
          ..addAll(polygons);
        _selectedPolygon = null;
        if (center != null) {
          _fallbackCenter = center;
        }
        _statusMessage = 'জিপিএস সিগন্যালের জন্য অপেক্ষা করা হচ্ছে...';
      });
      if (center != null) {
        _moveMap(center, 16);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'কার্যালয়ের সীমানা লোড করা যায়নি।';
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

  Future<void> _loadCustomPlaces() async {
    if (_prefs == null) return;
    final stored = _prefs!.getString(_customPlacesStorageKey);
    if (stored == null) return;
    try {
      final decoded = json.decode(stored) as List<dynamic>;
      final places = decoded
          .whereType<Map<String, dynamic>>()
          .map(_CustomPlace.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _customPlaces
          ..clear()
          ..addAll(places);
      });
    } catch (_) {
      // ignore malformed stored data
    }
  }

  Future<void> _persistHistory() async {
    if (_prefs == null) return;
    final encoded = json.encode(_history.map((e) => e.toJson()).toList());
    await _prefs!.setString(_historyStorageKey, encoded);
  }

  Future<void> _persistCustomPlaces() async {
    if (_prefs == null) return;
    final encoded =
        json.encode(_customPlaces.map((place) => place.toJson()).toList());
    await _prefs!.setString(_customPlacesStorageKey, encoded);
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
              _statusMessage = 'অবস্থান পাওয়ার সময় ত্রুটি ঘটেছে।';
            });
          },
        );
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      setState(() {
        _statusMessage = 'এই ডিভাইসে অবস্থান সেবা বন্ধ আছে।';
        _errorMessage = 'আপনার অবস্থান অনুসরণ করতে অবস্থান সেবা চালু করুন।';
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
        _statusMessage = 'অবস্থান অনুমতি প্রত্যাখ্যান করা হয়েছে।';
        _errorMessage = 'জিপিএস ট্র্যাকিং চালু রাখতে অবস্থান অনুমতি দিন।';
      });
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      setState(() {
        _permissionDenied = true;
        _statusMessage = 'অবস্থান অনুমতি স্থায়ীভাবে প্রত্যাখ্যান করা হয়েছে।';
        _errorMessage =
            'চালিয়ে যেতে সিস্টেম সেটিংস থেকে অবস্থান অনুমতি সক্রিয় করুন।';
      });
      return false;
    }

    if (!mounted) return true;
    setState(() {
      _permissionDenied = false;
      _errorMessage = null;
      if (_statusMessage == 'সীমানা লোড হচ্ছে...') {
        _statusMessage = 'জিপিএস সিগন্যালের জন্য অপেক্ষা করা হচ্ছে...';
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
        statusMessage: 'সীমানার তথ্য পাওয়া যায়নি।',
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
        statusMessage: '✅ আপনি লক্ষ্য এলাকায় আছেন!',
      );
    }

    final distanceText = minDistance.isFinite
        ? _formatKilometers(minDistance / 1000)
        : '—';
    return _GeofenceResult(
      inside: false,
      statusMessage: '❌ আপনি লক্ষ্য এলাকায় নেই। দূরত্ব: $distanceText।',
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
          'ক্যালিব্রেশন চলছে — সামান্য নড়াচড়া করুন এবং জিপিএস স্থিতিশীল হওয়ার জন্য অপেক্ষা করুন...';
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
        _errorMessage = 'ক্যালিব্রেশন ব্যর্থ হয়েছে: $e';
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
    final Color baseBorderColor = Colors.blue.shade600;
    final Color selectedBorderColor = Colors.orange.shade700;
    final Color baseFillColor = const Color(0xFF42A5F5).withOpacity(0.2);
    final Color selectedFillColor = const Color(0xFFFFB74D).withOpacity(0.35);

    return _polygons
        .where((polygon) => polygon.outer.isNotEmpty)
        .map(
          (polygon) {
            final bool isSelected = identical(polygon, _selectedPolygon);
            return Polygon(
              points: polygon.outer,
              holePointsList: polygon.holes,
              color: isSelected ? selectedFillColor : baseFillColor,
              borderColor: isSelected ? selectedBorderColor : baseBorderColor,
              borderStrokeWidth: isSelected ? 3.6 : 2.8,
              isFilled: true,
            );
          },
        )
        .toList();
  }

  Marker? _buildCurrentLocationMarker() {
    if (_currentLocation == null) {
      return null;
    }
    final accuracyValue = _currentAccuracy;
    final accuracyText = accuracyValue != null
        ? _formatMeters(accuracyValue, fractionDigits: 0)
        : 'উপলব্ধ নয়';
    return Marker(
      point: _currentLocation!,
      width: 48,
      height: 48,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: _onCurrentLocationMarkerTap,
        child: Tooltip(
          message: 'আপনি এখানে আছেন\nসঠিকতা: $accuracyText',
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
                    'সময়: ${_formatTimestamp(entry.timestampMs)}\nলক্ষ্য এলাকায় আছেন: ${entry.inside ? 'হ্যাঁ' : 'না'}\nসঠিকতা: ${_formatMeters(entry.accuracy, fractionDigits: 0)}',
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

  List<Marker> _buildCustomPlaceMarkers() {
    if (_customPlaces.isEmpty) {
      return const [];
    }

    return _customPlaces
        .map(
          (place) {
            final imageBytes = place.imageBytes;
            return Marker(
              point: place.location,
              width: 48,
              height: 72,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => _showCustomPlaceDetails(place),
                child: Tooltip(
                  message:
                      '${place.name.isEmpty ? 'Unnamed place' : place.name}\nCategory: ${place.category}\nAddress: ${place.address}',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (place.name.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            place.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (imageBytes != null) ...[
                        const SizedBox(height: 4),
                        CircleAvatar(
                          radius: 14,
                          backgroundImage: MemoryImage(imageBytes),
                        ),
                      ],
                      const SizedBox(height: 4),
                      const _GoogleStyleMarker(),
                    ],
                  ),
                ),
              ),
            );
          },
        )
        .toList();
  }

  void _onCurrentLocationMarkerTap() {
    final location = _currentLocation;
    if (location == null) {
      return;
    }
    final accuracyValue = _currentAccuracy;
    final accuracyText = accuracyValue != null
        ? _formatMeters(accuracyValue, fractionDigits: 1)
        : 'উপলব্ধ নয়';
    final insideText =
        _insideTarget ? 'আপনি লক্ষ্য এলাকায় আছেন' : 'আপনি লক্ষ্য এলাকায় নেই';
    _showMarkerDetails(
      title: 'আপনার বর্তমান অবস্থান',
      content: [
        Text('অক্ষাংশ: ${_formatCoordinate(location.latitude)}'),
        Text('দ্রাঘিমাংশ: ${_formatCoordinate(location.longitude)}'),
        Text('সঠিকতা: $accuracyText'),
        Text(insideText),
        const SizedBox(height: 8),
        Text(_statusMessage),
      ],
    );
  }

  _PolygonFeature? _polygonAt(LatLng point) {
    for (final polygon in _polygons) {
      if (_isPointInsidePolygon(point, polygon)) {
        return polygon;
      }
    }
    return null;
  }

  void _onPolygonTap(_PolygonFeature polygon) {
    if (!mounted) return;
    setState(() {
      _selectedPolygon = polygon;
      _skipNextMapTapClear = false;
    });
  }

  void _showCustomPlaceDetails(_CustomPlace place) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _PlaceDetailsSheet(place: place),
    );
  }

  void _onHistoryMarkerTap(LocationHistoryEntry entry) {
    final timestamp = _formatTimestamp(entry.timestampMs);
    final insideText = entry.inside ? 'হ্যাঁ' : 'না';
    _showMarkerDetails(
      title: 'সংরক্ষিত অবস্থান',
      content: [
        Text('অক্ষাংশ: ${_formatCoordinate(entry.latitude)}'),
        Text('দ্রাঘিমাংশ: ${_formatCoordinate(entry.longitude)}'),
        Text('সঠিকতা: ${_formatMeters(entry.accuracy, fractionDigits: 1)}'),
        Text('লক্ষ্য সীমানার ভেতরে: $insideText'),
        Text('সময়: $timestamp'),
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
              child: const Text('বন্ধ করুন'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard() {
    final accuracyValue = _currentAccuracy;
    final accuracyText = accuracyValue != null
        ? _formatMeters(accuracyValue, fractionDigits: 0)
        : 'অপেক্ষা চলছে...';

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
      const SnackBar(content: Text('বর্তমান অবস্থান এখনও পাওয়া যায়নি।')),
    );
  }

  Future<void> _startAddPlaceFlow() async {
    final result = await Navigator.of(context).push<_CustomPlace>(
      MaterialPageRoute(
        builder: (context) => _AddPlacePage(
          initialLocation: _currentLocation ?? _fallbackCenter,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _customPlaces.add(result);
    });
    await _persistCustomPlaces();

    if (!mounted) return;
    final displayName = result.name.isEmpty ? 'New place' : result.name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📍 "$displayName" added to the map.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMarker = _buildCurrentLocationMarker();
    final historyMarkers = _buildHistoryMarkers();
    final customPlaceMarkers = _buildCustomPlaceMarkers();

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
              tooltip: 'বর্তমান অবস্থানে যান',
              child: const Icon(Icons.my_location),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'calibrate_btn',
              onPressed: _permissionDenied ? null : _calibrateNow,
              label: const Text('এখন ক্যালিব্রেট করুন'),
              icon: const Icon(Icons.compass_calibration),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'add_place_btn',
              onPressed: _startAddPlaceFlow,
              label: const Text('Add place'),
              icon: const Icon(Icons.add_location_alt),
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
              onTap: (tapPosition, point) {
                if (_skipNextMapTapClear) {
                  _skipNextMapTapClear = false;
                  return;
                }
                final polygon = _polygonAt(point);
                if (polygon != null) {
                  _onPolygonTap(polygon);
                  return;
                }
                if (_selectedPolygon != null) {
                  setState(() {
                    _selectedPolygon = null;
                  });
                }
              },
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
              if (customPlaceMarkers.isNotEmpty)
                MarkerLayer(markers: customPlaceMarkers),
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
          if (_selectedPolygon != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: 12 + MediaQuery.of(context).padding.bottom,
                ),
                child: _SelectedPolygonCard(
                  polygon: _selectedPolygon!,
                  onClose: () {
                    setState(() {
                      _selectedPolygon = null;
                      _skipNextMapTapClear = false;
                    });
                  },
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

class _GoogleStyleMarker extends StatelessWidget {
  const _GoogleStyleMarker({
    this.color = const Color(0xFFE53935),
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.location_pin,
            color: color,
            size: 40,
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedPolygonCard extends StatelessWidget {
  const _SelectedPolygonCard({
    required this.polygon,
    required this.onClose,
  });

  final _PolygonFeature polygon;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _polygonReadableProperties(polygon);

    final String titleValue;
    final plotNumber = polygon.properties['plot_number'];
    if (plotNumber != null) {
      titleValue = 'প্লট ${_formatPropertyValue(plotNumber)}';
    } else {
      titleValue = 'প্লটের বিবরণ';
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      titleValue,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    tooltip: 'বন্ধ করুন',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (entries.isNotEmpty) const Divider(height: 20),
              ...entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          entry.key,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 7,
                        child: Text(
                          entry.value,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceDetailsSheet extends StatelessWidget {
  const _PlaceDetailsSheet({required this.place});

  final _CustomPlace place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = place.details();
    final imageBytes = place.imageBytes;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    place.name.isEmpty ? 'New place' : place.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (imageBytes != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  imageBytes,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            if (place.category.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  place.category,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        entry.key,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPlacePage extends StatefulWidget {
  const _AddPlacePage({
    super.key,
    required this.initialLocation,
  });

  final LatLng initialLocation;

  @override
  State<_AddPlacePage> createState() => _AddPlacePageState();
}

class _AddPlacePageState extends State<_AddPlacePage> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();
  final ImagePicker _imagePicker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _addressController;
  late final TextEditingController _locatedWithinController;
  late final TextEditingController _phoneController;
  late final TextEditingController _websiteController;
  late final TextEditingController _descriptionController;

  LatLng? _selectedLocation;
  late LatLng _mapCenter;
  Uint8List? _selectedImageBytes;
  String? _selectedImageFileName;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _categoryController = TextEditingController();
    _addressController = TextEditingController();
    _locatedWithinController = TextEditingController();
    _phoneController = TextEditingController();
    _websiteController = TextEditingController();
    _descriptionController = TextEditingController();
    _selectedLocation = widget.initialLocation;
    _mapCenter = widget.initialLocation;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _addressController.dispose();
    _locatedWithinController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _selectLocation(LatLng point) {
    setState(() {
      _selectedLocation = point;
    });
  }

  void _useMapCenter() {
    _selectLocation(_mapCenter);
  }

  Future<void> _showCategoryPicker() async {
    final selectedCategory = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        String searchQuery = '';
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  final matches = _placeCategories
                      .where(
                        (category) => category
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase()),
                      )
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                        child: Text(
                          'Select a category',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Search categories',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) {
                            setModalState(() {
                              searchQuery = value;
                            });
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      if (matches.isEmpty)
                        const Expanded(
                          child: Center(
                            child: Text('No categories found.'),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: matches.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final category = matches[index];
                              return ListTile(
                                title: Text(category),
                                onTap: () => Navigator.of(context).pop(category),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    if (selectedCategory != null) {
      setState(() {
        _categoryController.text = selectedCategory;
      });
    }
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageFileName = picked.name;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to select an image: $error')),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageFileName = null;
    });
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  String? _optionalText(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final location = _selectedLocation;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a point on the map.')),
      );
      return;
    }

    final place = _CustomPlace(
      name: _nameController.text.trim(),
      category: _categoryController.text.trim(),
      address: _addressController.text.trim(),
      location: location,
      locatedWithin: _optionalText(_locatedWithinController),
      phone: _optionalText(_phoneController),
      website: _optionalText(_websiteController),
      description: _optionalText(_descriptionController),
      createdAt: DateTime.now(),
      imageBase64:
          _selectedImageBytes != null ? base64Encode(_selectedImageBytes!) : null,
    );

    Navigator.of(context).pop(place);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final location = _selectedLocation;
    final locationSummary = location != null
        ? 'Selected point: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}'
        : 'Tap the map to choose a location.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a new place'),
        leading: const CloseButton(),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottomInset + 24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pick a location on the map',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 260,
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: location ?? widget.initialLocation,
                          initialZoom: 17,
                          onTap: (tapPosition, point) => _selectLocation(point),
                          onMapEvent: (event) {
                            _mapCenter = event.camera.center;
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c'],
                            userAgentPackageName: 'com.example.balumohol',
                          ),
                          if (location != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: location,
                                  width: 40,
                                  height: 40,
                                  child: const _GoogleStyleMarker(),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          locationSummary,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _useMapCenter,
                        icon: const Icon(Icons.center_focus_strong),
                        label: const Text('Use map center'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Place information',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Place name (required)',
                      hintText: 'e.g. Rahman Traders',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: _validateRequired,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _categoryController,
                    decoration: InputDecoration(
                      labelText: 'Category (required)',
                      hintText: 'e.g. Grocery store',
                      suffixIcon: IconButton(
                        tooltip: 'Browse categories',
                        icon: const Icon(Icons.list_alt),
                        onPressed: _showCategoryPicker,
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: _validateRequired,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address (required)',
                      hintText: 'Street, village, or house number',
                    ),
                    textInputAction: TextInputAction.next,
                    validator: _validateRequired,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locatedWithinController,
                    decoration: const InputDecoration(
                      labelText: 'Located within (optional)',
                      hintText: 'e.g. Market complex',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      hintText: 'e.g. 017XXXXXXXX',
                    ),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _websiteController,
                    decoration: const InputDecoration(
                      labelText: 'Website (optional)',
                      hintText: 'e.g. https://example.com',
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Photos (optional)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.add_a_photo),
                        label: const Text('Add photo'),
                      ),
                      if (_selectedImageFileName != null)
                        TextButton.icon(
                          onPressed: _removeImage,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove photo'),
                        ),
                      if (_selectedImageFileName != null)
                        Text(
                          _selectedImageFileName!,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                  if (_selectedImageBytes != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _selectedImageBytes!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Additional details (optional)',
                      hintText: 'Description, opening hours, notes',
                    ),
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Save place'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
  const _PolygonFeature({
    required this.id,
    required this.outer,
    required this.holes,
    required this.properties,
  });

  final String id;
  final List<LatLng> outer;
  final List<List<LatLng>> holes;
  final Map<String, dynamic> properties;
}

class _CustomPlace {
  const _CustomPlace({
    required this.name,
    required this.category,
    required this.address,
    required this.location,
    this.locatedWithin,
    this.phone,
    this.website,
    this.description,
    required this.createdAt,
    this.imageBase64,
  });

  factory _CustomPlace.fromJson(Map<String, dynamic> json) {
    final latitude = (json['lat'] as num?)?.toDouble();
    final longitude = (json['lng'] as num?)?.toDouble();
    final createdAtMs = json['createdAt'] as int?;

    return _CustomPlace(
      name: (json['name'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? '').trim(),
      address: (json['address'] as String? ?? '').trim(),
      location: LatLng(latitude ?? 0, longitude ?? 0),
      locatedWithin: (json['locatedWithin'] as String?).emptyToNull(),
      phone: (json['phone'] as String?).emptyToNull(),
      website: (json['website'] as String?).emptyToNull(),
      description: (json['description'] as String?).emptyToNull(),
      createdAt: createdAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
          : DateTime.now(),
      imageBase64: (json['image'] as String?).emptyToNull(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'address': address,
      'lat': location.latitude,
      'lng': location.longitude,
      'locatedWithin': locatedWithin,
      'phone': phone,
      'website': website,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'image': imageBase64,
    };
  }

  final String name;
  final String category;
  final String address;
  final LatLng location;
  final String? locatedWithin;
  final String? phone;
  final String? website;
  final String? description;
  final DateTime createdAt;
  final String? imageBase64;

  Uint8List? get imageBytes {
    final data = imageBase64;
    if (data == null || data.isEmpty) {
      return null;
    }
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  List<MapEntry<String, String>> details() {
    final entries = <MapEntry<String, String>>[
      MapEntry('Category', category),
      MapEntry('Address', address),
    ];

    if (locatedWithin != null && locatedWithin!.isNotEmpty) {
      entries.add(MapEntry('Located within', locatedWithin!));
    }
    if (phone != null && phone!.isNotEmpty) {
      entries.add(MapEntry('Phone', phone!));
    }
    if (website != null && website!.isNotEmpty) {
      entries.add(MapEntry('Website', website!));
    }
    if (description != null && description!.isNotEmpty) {
      entries.add(MapEntry('Details', description!));
    }
    entries.add(
      MapEntry('Added on', _formatTimestampEnglish(createdAt.millisecondsSinceEpoch)),
    );
    entries.add(
      MapEntry(
        'Coordinates',
        '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
      ),
    );
    return entries;
  }
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

const List<String> _banglaDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

String _toBanglaDigits(String value) {
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

String _formatNumber(num value, {int fractionDigits = 0}) {
  String text;
  if (fractionDigits <= 0) {
    text = value.round().toString();
  } else {
    text = _trimTrailingZeros(value.toStringAsFixed(fractionDigits));
  }
  return _toBanglaDigits(text);
}

String _formatMeters(num value, {int fractionDigits = 0}) {
  return '${_formatNumber(value, fractionDigits: fractionDigits)} মিটার';
}

String _formatKilometers(double value, {int fractionDigits = 2}) {
  return '${_formatNumber(value, fractionDigits: fractionDigits)} কিমি';
}

String _formatCoordinate(double value) {
  return _formatNumber(value, fractionDigits: 6);
}

String _formatTimestamp(int timestampMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
  final year = dt.year.toString().padLeft(4, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final second = dt.second.toString().padLeft(2, '0');
  return _toBanglaDigits('$year-$month-$day $hour:$minute:$second');
}

String _formatTimestampEnglish(int timestampMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
  final year = dt.year.toString().padLeft(4, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final second = dt.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

List<MapEntry<String, String>> _polygonReadableProperties(
    _PolygonFeature polygon) {
  const preferredOrder = <String>[
    'plot_number',
    'mouza_name',
    'upazila',
    'Remarks',
    'Shape_Length',
    'Shape_Area',
  ];

  final props = polygon.properties;
  final seen = <String>{};
  final ordered = <MapEntry<String, dynamic>>[];

  for (final key in preferredOrder) {
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
      .where((entry) => !_isNullOrEmpty(entry.value))
      .map(
        (entry) => MapEntry(
          _prettifyPropertyKey(entry.key),
          _formatPropertyValue(entry.value),
        ),
      )
      .toList();
}

bool _isNullOrEmpty(dynamic value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable || value is Map) return value.isEmpty;
  return false;
}

String _prettifyPropertyKey(String key) {
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

String _formatPropertyValue(dynamic value) {
  if (value == null) {
    return 'উপলব্ধ নয়';
  }
  if (value is int) {
    return _formatNumber(value, fractionDigits: 0);
  }
  if (value is double) {
    final fractionDigits = (value - value.roundToDouble()).abs() < 1e-6 ? 0 : 2;
    return _formatNumber(value, fractionDigits: fractionDigits);
  }
  if (value is num) {
    return _formatNumber(value, fractionDigits: 2);
  }
  if (value is String) {
    return _toBanglaDigits(value.trim());
  }
  return value.toString();
}

String _formatLatLng(LatLng point, {int fractionDigits = 6}) {
  final latText = _formatNumber(point.latitude, fractionDigits: fractionDigits);
  final lngText = _formatNumber(point.longitude, fractionDigits: fractionDigits);
  return '$latText, $lngText';
}

extension _NullableStringUtils on String? {
  String? emptyToNull() {
    final value = this;
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

List<_PolygonFeature> _parsePolygons(Map<String, dynamic> data) {
  final features = data['features'] as List<dynamic>? ?? [];
  final polygons = <_PolygonFeature>[];

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

_PolygonFeature _polygonFromCoords({
  required String id,
  required List<List<dynamic>> coordinates,
  required Map<String, dynamic> properties,
}) {
  if (coordinates.isEmpty) {
    return _PolygonFeature(
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
  return _PolygonFeature(
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
