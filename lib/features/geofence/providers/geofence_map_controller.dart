import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:balumohol/core/language/localized_text.dart';
import 'package:balumohol/core/location/location_service.dart';
import 'package:balumohol/core/storage/preferences_service.dart';
import 'package:balumohol/core/utils/formatting.dart';
import 'package:balumohol/features/geofence/data/geofence_api_service.dart';
import 'package:balumohol/features/geofence/constants.dart';
import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/models/geofence_result.dart';
import 'package:balumohol/features/geofence/models/location_history_entry.dart';
import 'package:balumohol/features/geofence/models/polygon_feature.dart';
import 'package:balumohol/features/geofence/models/polygon_field_template.dart';
import 'package:balumohol/features/geofence/models/position_sample.dart';
import 'package:balumohol/features/geofence/models/user_polygon.dart';
import 'package:balumohol/features/geofence/utils/geo_utils.dart';

class GeofenceMapController extends ChangeNotifier {
  GeofenceMapController({
    required LocationService locationService,
    required PreferencesService preferencesService,
    required GeofenceApiService apiService,
  })  : _locationService = locationService,
        _preferences = preferencesService,
        _apiService = apiService;

  static const LocalizedText _loadingBoundariesMessage = LocalizedText(
    bangla: 'সীমানা লোড হচ্ছে...',
    english: 'Loading boundaries...',
  );
  static const LocalizedText _calibratingStatusMessage = LocalizedText(
    bangla:
        'ক্যালিব্রেশন চলছে — সামান্য নড়াচড়া করুন এবং জিপিএস স্থিতিশীল হওয়ার জন্য অপেক্ষা করুন...',
    english:
        'Calibrating — move slightly and wait for the GPS to stabilize...',
  );
  static const LocalizedText _waitingForGpsStatusMessage = LocalizedText(
    bangla: 'জিপিএস সিগন্যালের জন্য অপেক্ষা করা হচ্ছে...',
    english: 'Waiting for GPS signal...',
  );
  static const LocalizedText _failedToLoadBoundariesStatusMessage =
      LocalizedText(
    bangla: 'কার্যালয়ের সীমানা লোড করা যায়নি।',
    english: 'Failed to load office boundaries.',
  );
  static const LocalizedText _locationErrorStatusMessage = LocalizedText(
    bangla: 'অবস্থান পাওয়ার সময় ত্রুটি ঘটেছে।',
    english: 'An error occurred while fetching the location.',
  );
  static const LocalizedText _locationServicesDisabledStatusMessage =
      LocalizedText(
    bangla: 'এই ডিভাইসে অবস্থান সেবা বন্ধ আছে।',
    english: 'Location services are disabled on this device.',
  );
  static const LocalizedText _locationPermissionDeniedStatusMessage =
      LocalizedText(
    bangla: 'অবস্থান অনুমতি প্রত্যাখ্যান করা হয়েছে।',
    english: 'Location permission was denied.',
  );
  static const LocalizedText _locationPermissionPermanentlyDeniedStatusMessage =
      LocalizedText(
    bangla: 'অবস্থান অনুমতি স্থায়ীভাবে প্রত্যাখ্যান করা হয়েছে।',
    english: 'Location permission was permanently denied.',
  );
  static const LocalizedText _noBoundaryDataStatusMessage = LocalizedText(
    bangla: 'সীমানার তথ্য পাওয়া যায়নি।',
    english: 'No boundary information available.',
  );
  static const LocalizedText _loadingMouzaListStatusMessage = LocalizedText(
    bangla: 'মৌজা তালিকা লোড হচ্ছে...',
    english: 'Loading mouza list...',
  );
  static const LocalizedText _failedToLoadMouzaListStatusMessage =
      LocalizedText(
    bangla: 'মৌজা তালিকা লোড করা যায়নি।',
    english: 'Failed to load mouza list.',
  );
  static const LocalizedText _loadingMouzaPolygonsStatusMessage =
      LocalizedText(
    bangla: 'মৌজার প্লট তথ্য লোড হচ্ছে...',
    english: 'Loading mouza plot data...',
  );
  static const LocalizedText _failedToLoadMouzaPolygonsStatusMessage =
      LocalizedText(
    bangla: 'মৌজার প্লট তথ্য লোড ব্যর্থ হয়েছে।',
    english: 'Failed to load mouza plot data.',
  );

  void _refreshVisiblePolygons({bool notify = true}) {
    _visiblePolygons
      ..clear()
      ..addAll([
        ..._outputPolygons,
        if (_showBoundary) ..._boundaryPolygons,
        ..._mouzaPolygons.where(
          (polygon) =>
              _selectedMouzaNames.contains(_mouzaNameForPolygon(polygon)),
        ),
        if (_showOtherPolygons) ..._otherPolygons,
        ..._userPolygons.map(_userPolygonToFeature),
      ]);
    _geofencePolygons
      ..clear()
      ..addAll(
        _visiblePolygons.where((polygon) => polygon.outer.isNotEmpty),
      );
    if (notify) {
      _notifySafely();
    }
  }

  final MapController mapController = MapController();

  final List<PolygonFeature> _visiblePolygons = [];
  final List<PolygonFeature> _geofencePolygons = [];
  final List<PolygonFeature> _outputPolygons = [];
  final List<PolygonFeature> _boundaryPolygons = [];
  final List<PolygonFeature> _mouzaPolygons = [];
  final List<PolygonFeature> _otherPolygons = [];
  final Map<String, List<String>> _upazilaMouzaNames = {};
  String? _selectedUpazila;
  bool _loadingUpazilas = false;
  String? _upazilaLoadError;
  final Map<String, Map<String, List<PolygonFeature>>> _mouzaPolygonCache = {};
  final Set<String> _loadingMouzaKeys = <String>{};
  final List<PolygonFieldTemplate> _polygonTemplates = [];
  final SplayTreeSet<String> _availableMouzaNames = SplayTreeSet<String>(
    (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );
  final Set<String> _selectedMouzaNames = <String>{};
  final List<PositionSample> _samples = [];
  final List<LocationHistoryEntry> _history = [];
  final List<LatLng> _trackingPath = [];
  final List<CustomPlace> _customPlaces = [];
  final List<UserPolygon> _userPolygons = [];
  bool _showBoundary = false;
  bool _showOtherPolygons = false;

  LatLng? _currentLocation;
  double? _currentAccuracy;
  double? _currentHeading;
  bool _insideTarget = false;
  LocalizedText _statusMessage = _loadingBoundariesMessage;
  String? _errorMessage;
  bool _mapReady = false;
  bool _permissionDenied = false;
  bool _hasCenteredOnUser = false;
  bool _initialised = false;
  bool _trackingActive = false;

  LatLng _fallbackCenter = const LatLng(23.8103, 90.4125);
  LatLng? _pendingCenter;
  double? _pendingZoom;
  double? _pendingRotation;
  PolygonFeature? _selectedPolygon;
  PolygonFeature? _primaryPolygon;
  LatLng? _primaryCenter;

  final LocationService _locationService;
  final PreferencesService _preferences;
  final GeofenceApiService _apiService;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _historyTimer;

  bool _disposed = false;

  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;
    await _preferences.init();
    await _loadGeoJsonBoundary();
    await _loadHistory();
    await _loadCustomPlaces();
    await _loadPolygonTemplates();
    await _loadUserPolygons();
    await _startLocationTracking();
    unawaited(_loadUpazilaMouzas());
  }

  @override
  void dispose() {
    _disposed = true;
    _historyTimer?.cancel();
    _positionSubscription?.cancel();
    _apiService.dispose();
    super.dispose();
  }

  List<PolygonFeature> get polygons => List.unmodifiable(_visiblePolygons);
  List<PolygonFeature> get boundaryPolygons =>
      List.unmodifiable(_boundaryPolygons);
  List<PolygonFeature> get mouzaPolygons => List.unmodifiable(_mouzaPolygons);
  List<PolygonFeature> get otherPolygons => List.unmodifiable(_otherPolygons);
  List<String> get availableMouzaNames =>
      List.unmodifiable(_availableMouzaNames.toList(growable: false));
  Set<String> get selectedMouzaNames => Set.unmodifiable(_selectedMouzaNames);
  List<String> get upazilaNames =>
      List.unmodifiable(_upazilaMouzaNames.keys.toList(growable: false));
  String? get selectedUpazila => _selectedUpazila;
  bool get isLoadingUpazilas => _loadingUpazilas;
  String? get upazilaLoadError => _upazilaLoadError;
  bool isMouzaLoading(String mouza) {
    final upazila = _selectedUpazila;
    if (upazila == null) return false;
    return _loadingMouzaKeys.contains(_cacheKey(upazila, mouza));
  }
  List<LocationHistoryEntry> get history => List.unmodifiable(_history);
  List<CustomPlace> get customPlaces => List.unmodifiable(_customPlaces);
  List<LatLng> get trackingPath => List.unmodifiable(_trackingPath);
  LatLng? get trackingDirectionPoint =>
      _trackingPath.isEmpty ? null : _trackingPath.last;
  double? get trackingDirectionRadians {
    if (_trackingPath.length < 2) {
      return null;
    }
    final previous = _trackingPath[_trackingPath.length - 2];
    final current = _trackingPath.last;
    final deltaLat = current.latitude - previous.latitude;
    final deltaLon = current.longitude - previous.longitude;
    if (deltaLat.abs() < 1e-9 && deltaLon.abs() < 1e-9) {
      return null;
    }
    return math.atan2(deltaLon, deltaLat);
  }
  List<UserPolygon> get userPolygons => List.unmodifiable(_userPolygons);
  List<PolygonFieldTemplate> get polygonTemplates =>
      List.unmodifiable(_polygonTemplates);

  UserPolygon? userPolygonById(String id) {
    for (final polygon in _userPolygons) {
      if (polygon.id == id) {
        return polygon;
      }
    }
    return null;
  }

  UserPolygon? userPolygonForFeatureId(String featureId) {
    const prefix = 'user_';
    if (!featureId.startsWith(prefix)) {
      return null;
    }
    final polygonId = featureId.substring(prefix.length);
    return userPolygonById(polygonId);
  }

  LatLng? get currentLocation => _currentLocation;
  double? get currentAccuracy => _currentAccuracy;
  double? get currentHeading => _currentHeading;
  bool get insideTarget => _insideTarget;
  LocalizedText get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  bool get permissionDenied => _permissionDenied;
  LatLng get fallbackCenter => _fallbackCenter;
  PolygonFeature? get selectedPolygon => _selectedPolygon;
  LatLng? get primaryCenter => _primaryCenter;
  bool get isTracking => _trackingActive;
  bool get showBoundary => _showBoundary;
  bool get showOtherPolygons => _showOtherPolygons;

  String? displayNameForPolygon(PolygonFeature polygon) {
    return polygonDisplayName(polygon);
  }

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
    highlightPolygon(null);

    final primaryPolygons =
        _outputPolygons.where((polygon) => polygon.outer.isNotEmpty).toList();
    if (primaryPolygons.isNotEmpty) {
      final bounds = _boundsForPolygons(primaryPolygons);
      if (bounds != null) {
        final center =
            computeBoundsCenter(primaryPolygons) ?? bounds.center;
        final zoom = (_zoomForBounds(bounds) - 0.6).clamp(5, 18).toDouble();
        moveMap(center, zoom);
        return;
      }
    }

    final targetPolygon = _primaryPolygon;
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

    _statusMessage = _calibratingStatusMessage;
    _hasCenteredOnUser = false;
    _errorMessage = null;
    _samples.clear();
    _notifySafely();

    try {
      final position = await _locationService.getCurrentPosition(
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

  Future<void> addUserPolygon(UserPolygon polygon) async {
    _userPolygons.add(polygon);
    _refreshVisiblePolygons();
    await _persistUserPolygons();
  }

  Future<void> updateUserPolygon(UserPolygon updated) async {
    final index = _userPolygons.indexWhere((polygon) => polygon.id == updated.id);
    if (index == -1) {
      return;
    }
    _userPolygons[index] = updated;
    _refreshVisiblePolygons();
    await _persistUserPolygons();
  }

  Future<void> removeUserPolygon(String polygonId) async {
    final previousLength = _userPolygons.length;
    _userPolygons.removeWhere((polygon) => polygon.id == polygonId);
    if (_userPolygons.length == previousLength) {
      return;
    }
    _refreshVisiblePolygons();
    await _persistUserPolygons();
  }

  Future<void> addPolygonTemplate(PolygonFieldTemplate template) async {
    final index = _polygonTemplates.indexWhere((item) => item.id == template.id);
    if (index >= 0) {
      _polygonTemplates[index] = template;
    } else {
      _polygonTemplates.add(template);
    }
    _notifySafely();
    await _persistPolygonTemplates();
  }

  Future<void> removePolygonTemplate(String templateId) async {
    final previousLength = _polygonTemplates.length;
    _polygonTemplates.removeWhere((template) => template.id == templateId);
    if (_polygonTemplates.length == previousLength) {
      return;
    }
    _notifySafely();
    await _persistPolygonTemplates();
  }

  Future<void> removeCustomPlace(CustomPlace place) async {
    final index = _customPlaces.indexOf(place);
    if (index == -1) {
      return;
    }
    _customPlaces.removeAt(index);
    _notifySafely();
    await _persistCustomPlaces();
  }

  Future<void> updateCustomPlace(
    CustomPlace original,
    CustomPlace updated,
  ) async {
    final index = _customPlaces.indexOf(original);
    if (index == -1) {
      return;
    }
    _customPlaces[index] = updated;
    _notifySafely();
    await _persistCustomPlaces();
  }

  void setShowBoundary(bool value) {
    if (_showBoundary == value) {
      return;
    }
    _showBoundary = value;
    _refreshVisiblePolygons();
    if (value) {
      final polygon = _firstNonEmptyPolygon(_boundaryPolygons);
      if (polygon != null) {
        focusPolygon(polygon, highlight: false);
      }
    }
  }

  void setShowOtherPolygons(bool value) {
    if (_showOtherPolygons == value) {
      return;
    }
    _showOtherPolygons = value;
    _refreshVisiblePolygons();
    if (value) {
      final polygon = _firstNonEmptyPolygon(_otherPolygons);
      if (polygon != null) {
        focusPolygon(polygon, highlight: false);
      }
    }
  }

  void setSelectedMouzas(Iterable<String> mouzas) {
    final previousSelection = Set<String>.from(_selectedMouzaNames);
    final filtered = mouzas
        .where((name) => _availableMouzaNames.contains(name))
        .toSet();
    if (_selectedMouzaNames.length == filtered.length &&
        _selectedMouzaNames.containsAll(filtered)) {
      return;
    }
    _selectedMouzaNames
      ..clear()
      ..addAll(filtered);
    _refreshVisiblePolygons();

    final newlySelected = filtered.difference(previousSelection);
    if (newlySelected.isNotEmpty) {
      _loadSelectedMouzaPolygons(
        newlySelected: newlySelected,
        focusTarget: newlySelected.first,
      );
    }
  }

  void selectAllMouzas() {
    setSelectedMouzas(_availableMouzaNames);
  }

  void clearMouzaSelection() {
    _selectedMouzaNames.clear();
    _refreshVisiblePolygons();
  }

  Future<bool> startTracking({bool reset = true}) async {
    if (_trackingActive) {
      return true;
    }
    if (_currentLocation == null || _currentAccuracy == null) {
      return false;
    }

    if (reset) {
      _history.clear();
      _trackingPath.clear();
      await _persistHistory();
    }

    _trackingActive = true;
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(
      historyInterval,
      (_) => _recordHistoryEntry(),
    );

    await _recordHistoryEntry(force: true);
    _notifySafely();
    return true;
  }

  void stopTracking() {
    if (!_trackingActive) {
      return;
    }
    _trackingActive = false;
    _historyTimer?.cancel();
    _historyTimer = null;
    _notifySafely();
  }

  void highlightPolygon(PolygonFeature? polygon) {
    _selectedPolygon = polygon;
    _notifySafely();
  }

  void focusPolygon(PolygonFeature polygon, {bool highlight = true}) {
    if (highlight) {
      highlightPolygon(polygon);
    }
    final bounds = _boundsForPolygon(polygon);
    if (bounds == null) {
      return;
    }
    final center = polygonCentroid(polygon) ?? bounds.center;
    final targetZoom = (_zoomForBounds(bounds) - 0.8).clamp(5, 18).toDouble();
    moveMap(center, targetZoom);
  }

  void focusMouza(String mouzaName) {
    _focusOnMouza(mouzaName, highlight: false);
  }

  PolygonFeature? polygonAt(LatLng point) {
    for (final polygon in _visiblePolygons) {
      if (isPointInsidePolygon(point, polygon)) {
        return polygon;
      }
    }
    return null;
  }

  void _focusOnMouza(String mouzaName, {bool highlight = false}) {
    final matching = _mouzaPolygons
        .where((polygon) => _mouzaNameForPolygon(polygon) == mouzaName)
        .toList();
    if (matching.isEmpty) {
      return;
    }

    final focusPolygons =
        matching.where((polygon) => polygon.outer.isNotEmpty).toList();
    final polygons = focusPolygons.isNotEmpty ? focusPolygons : matching;
    final bounds = _boundsForPolygons(polygons);
    if (bounds == null) {
      return;
    }

    final center = computeBoundsCenter(polygons) ?? bounds.center;
    if (highlight) {
      final highlighted = _findCentralPolygon(polygons, center) ?? polygons.first;
      highlightPolygon(highlighted);
    }

    final zoom = (_zoomForBounds(bounds) - 0.8).clamp(5, 18).toDouble();
    moveMap(center, zoom);
  }

  PolygonFeature? _firstNonEmptyPolygon(List<PolygonFeature> polygons) {
    for (final polygon in polygons) {
      if (polygon.outer.isNotEmpty) {
        return polygon;
      }
    }
    return polygons.isNotEmpty ? polygons.first : null;
  }

  Future<void> _loadGeoJsonBoundary() async {
    try {
      final boundaryRaw = await rootBundle.loadString(
        'assets/Daulatpur_Sheet_Boundary_WGS1984.geojson',
      );
      final Map<String, dynamic> boundaryData =
          json.decode(boundaryRaw) as Map<String, dynamic>;

      final outputRaw = await rootBundle.loadString(
        'assets/output.geojson',
      );

      final Map<String, dynamic> outputData =
          json.decode(outputRaw) as Map<String, dynamic>;

      final boundaryPolygons = _withPrefixedIds(
        parsePolygons(boundaryData),
        prefix: 'boundary',
        layerType: 'boundary',
      );
      final outputPolygons = _withPrefixedIds(
        parsePolygons(outputData),
        prefix: 'output',
        layerType: 'output',
      );

      _outputPolygons
        ..clear()
        ..addAll(outputPolygons.where((polygon) => polygon.outer.isNotEmpty));

      _boundaryPolygons
        ..clear()
        ..addAll(boundaryPolygons);

      _mouzaPolygons.clear();
      _otherPolygons.clear();
      _availableMouzaNames.clear();
      _selectedMouzaNames.clear();

      _geofencePolygons
        ..clear()
        ..addAll(_outputPolygons);

      final combined = <PolygonFeature>[
        ..._outputPolygons,
        ..._boundaryPolygons,
        ..._mouzaPolygons,
        ..._otherPolygons,
      ];
      final center = computeBoundsCenter(combined);
      final centralPolygon = _findCentralPolygon(combined, center);
      final resolvedCenter = centralPolygon != null
          ? polygonCentroid(centralPolygon)
          : center;
      final outputPrimary = _firstNonEmptyPolygon(_outputPolygons);
      if (outputPrimary != null) {
        _primaryPolygon = outputPrimary;
        _primaryCenter = polygonCentroid(outputPrimary) ??
            _boundsForPolygon(outputPrimary)?.center ??
            center;
      } else {
        _primaryPolygon = centralPolygon;
        _primaryCenter = resolvedCenter ?? center;
      }
      _selectedPolygon = null;

      _refreshVisiblePolygons(notify: false);

      PolygonFeature? focusPolygon;
      if (_showBoundary && _boundaryPolygons.isNotEmpty) {
        focusPolygon = _boundaryPolygons.firstWhere(
          (polygon) => polygon.outer.isNotEmpty,
          orElse: () => _boundaryPolygons.first,
        );
      }
      focusPolygon ??= _primaryPolygon;
      if (focusPolygon == null) {
        if (combined.isNotEmpty) {
          focusPolygon = combined.firstWhere(
            (polygon) => polygon.outer.isNotEmpty,
            orElse: () => combined.first,
          );
        }
      }

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
      _statusMessage = _waitingForGpsStatusMessage;
      _notifySafely();
    } catch (e) {
      _statusMessage = _failedToLoadBoundariesStatusMessage;
      _errorMessage = e.toString();
      _notifySafely();
    }
  }

  Future<void> _loadUpazilaMouzas() async {
    if (_loadingUpazilas) return;
    final previousStatus = _statusMessage;
    _loadingUpazilas = true;
    _statusMessage = _loadingMouzaListStatusMessage;
    _notifySafely();

    try {
      final data = await _apiService.fetchUpazilaMouzas();
      _upazilaMouzaNames
        ..clear()
        ..addAll(data);

      if (_upazilaMouzaNames.isEmpty) {
        _selectedUpazila = null;
      } else if (_selectedUpazila == null ||
          !_upazilaMouzaNames.containsKey(_selectedUpazila)) {
        _selectedUpazila = _upazilaMouzaNames.keys.first;
      }

      _updateAvailableMouzaNames();
      _syncMouzaPolygonsFromCache();
      _upazilaLoadError = null;
      _statusMessage = previousStatus;
      _refreshVisiblePolygons();
    } catch (error) {
      _upazilaLoadError = error.toString();
      _statusMessage = _failedToLoadMouzaListStatusMessage;
      _notifySafely();
    } finally {
      _loadingUpazilas = false;
      if (_statusMessage == _loadingMouzaListStatusMessage) {
        _statusMessage = previousStatus;
      }
      _notifySafely();
    }
  }

  void setSelectedUpazila(String? upazila) {
    final changed = _selectedUpazila != upazila;
    _selectedUpazila = upazila;
    if (changed) {
      _selectedMouzaNames.clear();
    }
    _updateAvailableMouzaNames();
    _syncMouzaPolygonsFromCache();
    _refreshVisiblePolygons();
  }

  void _updateAvailableMouzaNames() {
    final upazila = _selectedUpazila;
    _availableMouzaNames.clear();
    if (upazila != null) {
      final mouzas = _upazilaMouzaNames[upazila];
      if (mouzas != null) {
        _availableMouzaNames.addAll(mouzas);
      }
    }

    final toRemove = _selectedMouzaNames
        .where((name) => !_availableMouzaNames.contains(name))
        .toList(growable: false);
    if (toRemove.isNotEmpty) {
      _selectedMouzaNames.removeAll(toRemove);
    }
  }

  void _syncMouzaPolygonsFromCache() {
    _mouzaPolygons.clear();
    final upazila = _selectedUpazila;
    if (upazila == null) {
      return;
    }
    final cache = _mouzaPolygonCache[upazila];
    if (cache == null) {
      return;
    }
    for (final polygons in cache.values) {
      _mouzaPolygons.addAll(polygons);
    }
  }

  void _loadSelectedMouzaPolygons({
    required Set<String> newlySelected,
    String? focusTarget,
  }) {
    final upazila = _selectedUpazila;
    if (upazila == null) {
      return;
    }
    for (final mouza in newlySelected) {
      unawaited(
        _fetchMouzaPolygons(
          upazila: upazila,
          mouza: mouza,
          focusOnLoad: focusTarget == mouza,
        ),
      );
    }
  }

  Future<void> _fetchMouzaPolygons({
    required String upazila,
    required String mouza,
    bool focusOnLoad = false,
  }) async {
    final perUpazila =
        _mouzaPolygonCache.putIfAbsent(upazila, () => <String, List<PolygonFeature>>{});
    if (perUpazila.containsKey(mouza)) {
      _syncMouzaPolygonsFromCache();
      if (focusOnLoad) {
        _focusOnMouza(mouza, highlight: true);
      }
      _refreshVisiblePolygons();
      return;
    }

    final key = _cacheKey(upazila, mouza);
    if (_loadingMouzaKeys.contains(key)) {
      return;
    }

    _loadingMouzaKeys.add(key);
    final previousStatus = _statusMessage;
    _statusMessage = _loadingMouzaPolygonsStatusMessage;
    _notifySafely();

    try {
      final polygons = await _apiService.fetchMouzaPolygons(
        upazila: upazila,
        mouza: mouza,
      );
      final filtered = polygons.where((polygon) => polygon.outer.isNotEmpty).toList();
      perUpazila[mouza] = _withPrefixedIds(
        filtered,
        prefix: 'mouza_${_sanitizeId(upazila)}_${_sanitizeId(mouza)}',
        layerType: 'mouza',
      );
      _syncMouzaPolygonsFromCache();
      _statusMessage = previousStatus;
      _refreshVisiblePolygons();
      if (focusOnLoad) {
        _focusOnMouza(mouza, highlight: true);
      }
    } catch (error) {
      _errorMessage = error.toString();
      _statusMessage = _failedToLoadMouzaPolygonsStatusMessage;
      _notifySafely();
    } finally {
      _loadingMouzaKeys.remove(key);
      if (_statusMessage == _loadingMouzaPolygonsStatusMessage) {
        _statusMessage = previousStatus;
      }
      _notifySafely();
    }
  }

  String _cacheKey(String upazila, String mouza) => '$upazila::$mouza';

  String _sanitizeId(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  }

  Future<void> _loadHistory() async {
    final stored = _preferences.getString(historyStorageKey);
    if (stored == null) return;
    try {
      final decoded = json.decode(stored) as List<dynamic>;
      final entries = decoded
          .map((e) => LocationHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _history
        ..clear()
        ..addAll(entries);
      _trackingPath
        ..clear()
        ..addAll(
          entries
              .map((entry) => LatLng(entry.latitude, entry.longitude))
              .toList(),
        );
      _notifySafely();
    } catch (_) {
      // ignore malformed history
    }
  }

  Future<void> _loadCustomPlaces() async {
    final stored = _preferences.getString(customPlacesStorageKey);
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

  Future<void> _loadPolygonTemplates() async {
    final stored = _preferences.getString(userPolygonTemplatesStorageKey);
    if (stored == null) return;
    try {
      final decoded = json.decode(stored) as List<dynamic>;
      final templates = decoded
          .whereType<Map<String, dynamic>>()
          .map(PolygonFieldTemplate.fromJson)
          .where((template) => template.name.isNotEmpty)
          .toList();
      _polygonTemplates
        ..clear()
        ..addAll(templates);
      _notifySafely();
    } catch (_) {
      // ignore malformed stored data
    }
  }

  Future<void> _loadUserPolygons() async {
    final stored = _preferences.getString(userPolygonsStorageKey);
    if (stored == null) return;
    try {
      final decoded = json.decode(stored) as List<dynamic>;
      final polygons = decoded
          .whereType<Map<String, dynamic>>()
          .map(UserPolygon.fromJson)
          .where((polygon) => polygon.points.length >= 3)
          .toList();
      _userPolygons
        ..clear()
        ..addAll(polygons);
      _refreshVisiblePolygons();
    } catch (_) {
      // ignore malformed stored data
    }
  }

  Future<void> _persistHistory() async {
    final encoded = json.encode(_history.map((e) => e.toJson()).toList());
    await _preferences.setString(historyStorageKey, encoded);
  }

  Future<void> _persistCustomPlaces() async {
    final encoded = json.encode(
      _customPlaces.map((place) => place.toJson()).toList(),
    );
    await _preferences.setString(customPlacesStorageKey, encoded);
  }

  Future<void> _persistPolygonTemplates() async {
    final encoded = json.encode(
      _polygonTemplates.map((template) => template.toJson()).toList(),
    );
    await _preferences.setString(userPolygonTemplatesStorageKey, encoded);
  }

  Future<void> _persistUserPolygons() async {
    final encoded = json.encode(
      _userPolygons.map((polygon) => polygon.toJson()).toList(),
    );
    await _preferences.setString(userPolygonsStorageKey, encoded);
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
        final distance = distanceBetweenCoordinates(
          startLatitude: overallCenter.latitude,
          startLongitude: overallCenter.longitude,
          endLatitude: centroid.latitude,
          endLongitude: centroid.longitude,
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

  _PolygonBounds? _boundsForPolygons(Iterable<PolygonFeature> polygons) {
    double? minLat;
    double? maxLat;
    double? minLng;
    double? maxLng;

    for (final polygon in polygons) {
      final bounds = _boundsForPolygon(polygon);
      if (bounds == null) {
        continue;
      }
      minLat = minLat == null ? bounds.minLat : math.min(minLat!, bounds.minLat);
      maxLat = maxLat == null ? bounds.maxLat : math.max(maxLat!, bounds.maxLat);
      minLng = minLng == null ? bounds.minLng : math.min(minLng!, bounds.minLng);
      maxLng = maxLng == null ? bounds.maxLng : math.max(maxLng!, bounds.maxLng);
    }

    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      return null;
    }

    return _PolygonBounds(
      minLat: minLat!,
      maxLat: maxLat!,
      minLng: minLng!,
      maxLng: maxLng!,
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

  Future<void> _recordHistoryEntry({bool force = false}) async {
    if (_currentLocation == null || _currentAccuracy == null) return;
    if (!_trackingActive && !force) return;
    final entry = LocationHistoryEntry(
      latitude: _currentLocation!.latitude,
      longitude: _currentLocation!.longitude,
      inside: _insideTarget,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      accuracy: _currentAccuracy!,
    );
    _history.add(entry);
    _trackingPath.add(_currentLocation!);
    if (_history.length > maxHistoryEntries) {
      _history.removeRange(0, _history.length - maxHistoryEntries);
    }
    if (_trackingPath.length > maxHistoryEntries) {
      _trackingPath.removeRange(0, _trackingPath.length - maxHistoryEntries);
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
        _locationService.getPositionStream(settings).listen(
      _handlePosition,
      onError: (Object error) {
        _errorMessage = error.toString();
        _statusMessage = _locationErrorStatusMessage;
        _notifySafely();
      },
    );
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await _locationService.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _statusMessage = _locationServicesDisabledStatusMessage;
      _errorMessage = 'আপনার অবস্থান অনুসরণ করতে অবস্থান সেবা চালু করুন।';
      _notifySafely();
      return false;
    }

    LocationPermission permission = await _locationService.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _locationService.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _permissionDenied = true;
      _statusMessage = _locationPermissionDeniedStatusMessage;
      _errorMessage = 'জিপিএস ট্র্যাকিং চালু রাখতে অবস্থান অনুমতি দিন।';
      _notifySafely();
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _permissionDenied = true;
      _statusMessage = _locationPermissionPermanentlyDeniedStatusMessage;
      _errorMessage =
          'চালিয়ে যেতে সিস্টেম সেটিংস থেকে অবস্থান অনুমতি সক্রিয় করুন।';
      _notifySafely();
      return false;
    }

    _permissionDenied = false;
    _errorMessage = null;
    if (_statusMessage == _loadingBoundariesMessage) {
      _statusMessage = _waitingForGpsStatusMessage;
    }
    _notifySafely();
    return true;
  }

  void _handlePosition(Position position) {
    final previousLocation = _currentLocation;
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
    final headingValue = position.heading;
    if (headingValue != null && headingValue >= 0) {
      _currentHeading = headingValue % 360;
    } else if (previousLocation != null &&
        (previousLocation.latitude != location.latitude ||
            previousLocation.longitude != location.longitude)) {
      final bearing = _locationService.bearingBetween(
        previousLocation.latitude,
        previousLocation.longitude,
        location.latitude,
        location.longitude,
      );
      if (!bearing.isNaN) {
        _currentHeading = (bearing + 360) % 360;
      }
    }
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
    if (_geofencePolygons.isEmpty) {
      return const GeofenceResult(
        inside: false,
        statusMessage: _noBoundaryDataStatusMessage,
      );
    }

    PolygonFeature? containingPolygon;
    double minDistance = double.infinity;

    for (final polygon in _geofencePolygons) {
      if (isPointInsidePolygon(position, polygon)) {
        containingPolygon = polygon;
        break;
      }
      minDistance = math.min(minDistance, distanceToPolygon(position, polygon));
    }

    if (containingPolygon != null) {
      final polygonName = polygonDisplayName(containingPolygon);
      final banglaLocationText =
          polygonName != null ? '$polygonName এলাকায়' : 'নির্ধারিত এলাকায়';
      final englishLocationText = polygonName != null
          ? 'the $polygonName area'
          : 'the designated area';
      return GeofenceResult(
        inside: true,
        statusMessage: LocalizedText(
          bangla: '✅ আপনি $banglaLocationText আছেন!',
          english: '✅ You are within $englishLocationText!',
        ),
      );
    }

    final distanceText = minDistance.isFinite
        ? formatKilometers(minDistance / 1000)
        : '—';
    return GeofenceResult(
      inside: false,
      statusMessage: LocalizedText(
        bangla: '❌ আপনি নির্ধারিত এলাকায় নেই। দূরত্ব: $distanceText।',
        english:
            '❌ You are outside the designated area. Distance: $distanceText.',
      ),
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

PolygonFeature _userPolygonToFeature(UserPolygon polygon) {
  final displayName = polygon.name.isNotEmpty
      ? polygon.name
      : 'ব্যবহারকারী পলিগন';
  final properties = <String, dynamic>{
    'display_name': displayName,
    'user_color': polygon.colorValue,
    'layer_type': 'ব্যবহারকারী পলিগন',
  };

  final usedKeys = properties.keys.toSet();
  for (final field in polygon.fields) {
    if (!field.hasContent) continue;
    var key = field.propertyKey;
    if (key.isEmpty) continue;
    var candidate = key;
    var index = 1;
    while (usedKeys.contains(candidate)) {
      index += 1;
      candidate = '$key ($index)';
    }
    properties[candidate] = field.propertyValue;
    usedKeys.add(candidate);
  }

  return PolygonFeature(
    id: 'user_${polygon.id}',
    outer: polygon.points,
    holes: const [],
    properties: properties,
  );
}

List<PolygonFeature> _withPrefixedIds(
  List<PolygonFeature> polygons, {
  required String prefix,
  String? layerType,
}) {
  final result = <PolygonFeature>[];
  for (int i = 0; i < polygons.length; i++) {
    final polygon = polygons[i];
    final properties = <String, dynamic>{
      ...polygon.properties,
      if (layerType != null) 'layer_type': layerType,
    };
    result.add(
      PolygonFeature(
        id: '${prefix}_$i',
        outer: polygon.outer,
        holes: polygon.holes,
        properties: properties,
      ),
    );
  }
  return result;
}

String? _mouzaNameForPolygon(PolygonFeature polygon) {
  final mouza = polygon.properties['mouza_name'];
  if (mouza == null) {
    return null;
  }
  return mouza.toString();
}

String? polygonDisplayName(PolygonFeature polygon) {
  final properties = polygon.properties;

  String? _stringValue(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  final displayName = _stringValue(properties['display_name']) ??
      _stringValue(properties['name']);
  if (displayName != null) {
    return displayName;
  }

  final mouzaName = _stringValue(properties['mouza_name']);
  if (mouzaName != null) {
    return mouzaName.replaceAll('_', ' ');
  }

  final plotNumber = _stringValue(properties['plot_number']);
  if (plotNumber != null) {
    return 'প্লট $plotNumber';
  }

  final layerType = _stringValue(properties['layer_type']);
  if (layerType != null) {
    return layerType;
  }

  return _stringValue(polygon.id);
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

  LatLng get center => LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
}
