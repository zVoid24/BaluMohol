import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:balumohol/core/language/language_controller.dart';
import 'package:balumohol/core/utils/formatting.dart';
import 'package:balumohol/features/geofence/constants.dart';
import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/models/location_history_entry.dart';
import 'package:balumohol/features/geofence/models/polygon_feature.dart';
import 'package:balumohol/features/geofence/models/user_polygon.dart';
import 'package:balumohol/features/geofence/presentation/pages/draw_polygon_page.dart';
import 'package:balumohol/features/geofence/presentation/widgets/current_location_indicator.dart';
import 'package:balumohol/features/geofence/presentation/widgets/custom_place_marker.dart';
import 'package:balumohol/features/geofence/presentation/widgets/place_details_sheet.dart';
import 'package:balumohol/features/geofence/presentation/widgets/polygon_details_sheet.dart';
import 'package:balumohol/features/geofence/providers/geofence_map_controller.dart';
import 'package:balumohol/features/geofence/utils/geo_utils.dart';
import 'package:balumohol/features/places/presentation/pages/add_place_page.dart';

class GeofenceMapPage extends StatefulWidget {
  const GeofenceMapPage({super.key});

  @override
  State<GeofenceMapPage> createState() => _GeofenceMapPageState();
}

enum _MapLayerType { hybrid, satellite, terrain, roadmap, osm }

class _BaseLayerOption {
  const _BaseLayerOption({
    required this.type,
    required this.banglaLabel,
    required this.englishLabel,
    required this.urlTemplate,
    this.subdomains,
    this.banglaSubtitle,
    this.englishSubtitle,
  });

  final _MapLayerType type;
  final String banglaLabel;
  final String englishLabel;
  final String urlTemplate;
  final List<String>? subdomains;
  final String? banglaSubtitle;
  final String? englishSubtitle;

  String label(AppLanguage language) =>
      language.isBangla ? banglaLabel : englishLabel;

  String? subtitle(AppLanguage language) =>
      language.isBangla ? banglaSubtitle : englishSubtitle;
}

const List<String> _googleSubdomains = <String>['mt0', 'mt1', 'mt2', 'mt3'];

const List<_BaseLayerOption> _baseLayerOptions = <_BaseLayerOption>[
  _BaseLayerOption(
    type: _MapLayerType.hybrid,
    banglaLabel: 'হাইব্রিড',
    englishLabel: 'Hybrid',
    banglaSubtitle: 'স্যাটেলাইট ছবি ও মানচিত্র লেবেল',
    englishSubtitle: 'Satellite imagery with labels',
    urlTemplate: 'https://{s}.google.com/vt/lyrs=s,h&x={x}&y={y}&z={z}',
    subdomains: _googleSubdomains,
  ),
  _BaseLayerOption(
    type: _MapLayerType.satellite,
    banglaLabel: 'স্যাটেলাইট',
    englishLabel: 'Satellite',
    banglaSubtitle: 'শুধু স্যাটেলাইট ছবি',
    englishSubtitle: 'Satellite imagery only',
    urlTemplate: 'https://{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
    subdomains: _googleSubdomains,
  ),
  _BaseLayerOption(
    type: _MapLayerType.terrain,
    banglaLabel: 'টেরেইন',
    englishLabel: 'Terrain',
    banglaSubtitle: 'ভূপ্রকৃতি ও উচ্চতার মানচিত্র',
    englishSubtitle: 'Topography and elevation',
    urlTemplate: 'https://{s}.google.com/vt/lyrs=p&x={x}&y={y}&z={z}',
    subdomains: _googleSubdomains,
  ),
  _BaseLayerOption(
    type: _MapLayerType.roadmap,
    banglaLabel: 'স্ট্যান্ডার্ড মানচিত্র',
    englishLabel: 'Standard map',
    banglaSubtitle: 'সাধারণ রাস্তা ও স্থান',
    englishSubtitle: 'Roads and places',
    urlTemplate: 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
    subdomains: _googleSubdomains,
  ),
  _BaseLayerOption(
    type: _MapLayerType.osm,
    banglaLabel: 'ওপেনস্ট্রিটম্যাপ',
    englishLabel: 'OpenStreetMap',
    banglaSubtitle: 'ওপেন সোর্স কমিউনিটি মানচিত্র',
    englishSubtitle: 'Open-source community map',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  ),
];

class _GeofenceMapPageState extends State<GeofenceMapPage> {
  static const double _customPlaceMarkerZoomThreshold = 14;
  static const double _customPlaceMarkerBaseWidth = 160;
  static const double _customPlaceMarkerBaseHeight = 64;

  bool _initialised = false;
  double _currentZoom = 15;
  CustomPlace? _selectedCustomPlace;
  bool _statusPanelCollapsed = true;
  _MapLayerType _selectedLayerType = _MapLayerType.hybrid;

  bool get _showCustomPlaceMarkers =>
      _currentZoom >= _customPlaceMarkerZoomThreshold;

  _BaseLayerOption get _selectedBaseLayer => _baseLayerOptions.firstWhere(
    (option) => option.type == _selectedLayerType,
  );

  String _text(AppLanguage language, String bangla, String english) {
    return language.isBangla ? bangla : english;
  }

  String _languageOptionSubtitle(
    AppLanguage currentLanguage,
    AppLanguage option,
  ) {
    return option.isBangla
        ? _text(
            currentLanguage,
            'অ্যাপের ভাষা বাংলা করুন',
            'Switch the app language to Bangla',
          )
        : _text(
            currentLanguage,
            'অ্যাপের ভাষা ইংরেজি করুন',
            'Switch the app language to English',
          );
  }

  @override
  void initState() {
    super.initState();
    _currentZoom = 15;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<GeofenceMapController>().initialize();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GeofenceMapController>();
    final language = context.watch<LanguageController>().language;
    final useBanglaDigits = language.isBangla;
    final currentMarker = _buildCurrentLocationMarker(controller);
    final historyMarkers = _buildHistoryMarkers(controller);
    final customPlaceMarkers = _showCustomPlaceMarkers
        ? _buildCustomPlaceMarkers(controller)
        : <Marker>[];
    final pathPoints = controller.trackingPath;
    final polygonLabelMarkers = _buildPolygonLabels(controller);
    final accuracyValue = controller.currentAccuracy;
    final accuracyText = accuracyValue != null
        ? formatMeters(
            accuracyValue,
            fractionDigits: 0,
            useBanglaDigits: useBanglaDigits,
            unitLabel: useBanglaDigits ? 'মিটার' : 'meters',
          )
        : _text(language, 'অপেক্ষা চলছে...', 'Fetching...');
    final bool isTracking = controller.isTracking;

    final VoidCallback? trackingCallback =
        isTracking || !controller.permissionDenied
        ? () => _toggleTracking(controller)
        : null;
    final VoidCallback? calibrateCallback = controller.permissionDenied
        ? null
        : () => controller.calibrateNow();

    return Scaffold(
      appBar: null,
      drawer: Drawer(
        child: _MapSidebar(
          controller: controller,
          isTracking: isTracking,
          language: language,
          onAddPlace: () => _startAddPlaceFlow(controller),
          onAddPolygon: () => _startPolygonDrawing(controller),
          onToggleTracking: trackingCallback,
          onCalibrate: calibrateCallback,
          onMouzaSelectionChanged: (selection) =>
              controller.setSelectedMouzas(selection),
          onSelectAllMouzas: controller.selectAllMouzas,
          onClearMouzas: controller.clearMouzaSelection,
          onToggleBoundary: controller.setShowBoundary,
          onToggleOtherPolygons: controller.setShowOtherPolygons,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'current_location_btn',
              onPressed: () => _goToCurrentLocation(controller),
              tooltip: _text(
                language,
                'বর্তমান অবস্থানে যান',
                'Go to current location',
              ),
              child: const Icon(Icons.my_location),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'compass_btn',
              onPressed: controller.resetRotation,
              tooltip: _text(
                language,
                'মানচিত্র উত্তরের দিকে ঘোরান',
                'Reset north',
              ),
              child: const Icon(Icons.explore),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'navigate_btn',
              onPressed: controller.centerOnPrimaryArea,
              icon: const Icon(Icons.layers),
              label: Text(_text(language, 'বালুমহাল', 'Balu Mohal')),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: controller.mapController,
            options: MapOptions(
              initialCenter: controller.fallbackCenter,
              initialZoom: 15,
              onTap: (tapPosition, point) async {
                final polygon = controller.polygonAt(point);
                if (polygon != null) {
                  await _showPolygonDetails(controller, polygon);
                  return;
                }
                controller.highlightPolygon(null);
              },
              onMapReady: controller.onMapReady,
              onMapEvent: (event) {
                final zoom = event.camera.zoom;
                if ((zoom - _currentZoom).abs() > 0.01) {
                  setState(() {
                    _currentZoom = zoom;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _selectedBaseLayer.urlTemplate,
                subdomains: _selectedBaseLayer.subdomains ?? const <String>[],
                userAgentPackageName: 'com.example.balumohol',
              ),
              if (controller.polygons.isNotEmpty)
                PolygonLayer(polygons: _buildPolygons(controller)),
              if (polygonLabelMarkers.isNotEmpty)
                MarkerLayer(markers: polygonLabelMarkers),
              if (pathPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: pathPoints,
                      strokeWidth: 4,
                      color: Colors.blueAccent.withOpacity(0.8),
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
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
                alignment: Alignment.topRight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _StatusPanel(
                      language: language,
                      collapsed: _statusPanelCollapsed,
                      onToggle: () {
                        setState(() {
                          _statusPanelCollapsed = !_statusPanelCollapsed;
                        });
                      },
                      accuracyText: accuracyText,
                      statusMessage: controller.statusMessage,
                      errorMessage: controller.errorMessage,
                    ),
                    const SizedBox(height: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _LayerControlButton(
                          onPressed: () => _showLayerSelector(language),
                        ),
                        const SizedBox(height: 12),
                        _LanguageControlButton(
                          language: language,
                          tooltip: _text(
                            language,
                            'অ্যাপের ভাষা নির্বাচন করুন',
                            'Choose app language',
                          ),
                          onPressed: () => _showLanguageSelector(language),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  elevation: 4,
                  shape: const CircleBorder(),
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceVariant.withOpacity(0.9),
                  child: Builder(
                    builder: (context) => IconButton(
                      tooltip: 'সাইডবার খুলুন',
                      icon: const Icon(Icons.menu),
                      onPressed: Scaffold.of(context).openDrawer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Polygon> _buildPolygons(GeofenceMapController controller) {
    final selectedId = controller.selectedPolygon?.id;
    final polygons =
        controller.polygons
            .where((polygon) => polygon.outer.isNotEmpty)
            .toList()
          ..sort(
            (a, b) =>
                _polygonLayerPriority(a).compareTo(_polygonLayerPriority(b)),
          );

    return polygons.map((polygon) {
      final bool isSelected = polygon.id == selectedId;
      final customColor = _customPolygonColor(polygon.properties);
      final layerType = polygon.properties['layer_type'];
      final Color fillColor;
      final Color borderColor;

      if (layerType == 'output') {
        fillColor = outputPolygonFillColor.withOpacity(isSelected ? 0.55 : 0.4);
        borderColor = outputPolygonBorderColor;
      } else if (customColor != null) {
        fillColor = customColor.withOpacity(isSelected ? 0.45 : 0.28);
        borderColor = customColor;
      } else {
        fillColor = isSelected
            ? polygonSelectedFillColor
            : polygonBaseFillColor;
        borderColor = isSelected
            ? polygonSelectedBorderColor
            : polygonBaseBorderColor;
      }

      return Polygon(
        points: polygon.outer,
        holePointsList: polygon.holes,
        color: fillColor,
        borderColor: borderColor,
        borderStrokeWidth: isSelected ? 3.6 : 2.8,
        isFilled: true,
      );
    }).toList();
  }

  int _polygonLayerPriority(PolygonFeature polygon) {
    final layerType = polygon.properties['layer_type'];
    if (layerType == 'output') {
      return 3;
    }
    if (layerType == 'boundary') {
      return 2;
    }
    if (layerType == 'mouza') {
      return 1;
    }
    return 0;
  }

  Color? _customPolygonColor(Map<String, dynamic> properties) {
    final value = properties['user_color'];
    if (value is int) {
      return Color(value);
    }
    if (value is num) {
      return Color(value.toInt());
    }
    return null;
  }

  List<Marker> _buildPolygonLabels(GeofenceMapController controller) {
    if (!controller.showBoundary) {
      return const [];
    }
    final polygons = controller.polygons.where((polygon) {
      final layerType = polygon.properties['layer_type'];
      return layerType == 'boundary';
    }).toList();
    if (polygons.isEmpty) {
      return const [];
    }
    final selectedId = controller.selectedPolygon?.id;
    final markers = <Marker>[];
    for (final polygon in polygons) {
      final centroid = polygonCentroid(polygon);
      if (centroid == null) continue;
      final label = controller.displayNameForPolygon(polygon);
      if (label == null || label.isEmpty) continue;
      final bool isSelected = polygon.id == selectedId;
      final customColor = _customPolygonColor(polygon.properties);
      markers.add(
        Marker(
          point: centroid,
          width: 220,
          height: 60,
          alignment: Alignment.center,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final baseTextStyle =
                  theme.textTheme.labelMedium ??
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
              final textColor = customColor ?? theme.colorScheme.onSurface;
              final textStyle = baseTextStyle.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              );
              return IgnorePointer(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: textStyle,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return markers;
  }

  Marker? _buildCurrentLocationMarker(GeofenceMapController controller) {
    final language = context.read<LanguageController>().language;
    final useBanglaDigits = language.isBangla;
    final location = controller.currentLocation;
    if (location == null) {
      return null;
    }
    final accuracyValue = controller.currentAccuracy;
    final accuracyText = accuracyValue != null
        ? formatMeters(
            accuracyValue,
            fractionDigits: 0,
            useBanglaDigits: useBanglaDigits,
            unitLabel: useBanglaDigits ? 'মিটার' : 'meters',
          )
        : _text(language, 'উপলব্ধ নয়', 'Not available');
    return Marker(
      point: location,
      width: 48,
      height: 48,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () => _showCurrentLocationDetails(controller),
        child: Tooltip(
          message: _text(
            language,
            'আপনি এখানে আছেন\nসঠিকতা: $accuracyText',
            'You are here\nAccuracy: $accuracyText',
          ),
          child: CurrentLocationIndicator(heading: controller.currentHeading),
        ),
      ),
    );
  }

  List<Marker> _buildHistoryMarkers(GeofenceMapController controller) {
    final language = context.read<LanguageController>().language;
    final useBanglaDigits = language.isBangla;
    if (controller.history.isEmpty) {
      return const [];
    }

    return controller.history
        .map(
          (entry) => Marker(
            point: LatLng(entry.latitude, entry.longitude),
            width: 20,
            height: 20,
            child: GestureDetector(
              onTap: () => _showHistoryEntryDetails(entry),
              child: Tooltip(
                message: _text(
                  language,
                  'সময়: ${formatTimestampBangla(entry.timestampMs)}\nলক্ষ্য এলাকায় আছেন: ${entry.inside ? 'হ্যাঁ' : 'না'}\nসঠিকতা: ${formatMeters(entry.accuracy, fractionDigits: 0)}',
                  'Time: ${formatTimestampLocalized(entry.timestampMs, useBanglaDigits: false)}\nInside target: ${entry.inside ? 'Yes' : 'No'}\nAccuracy: ${formatMeters(entry.accuracy, fractionDigits: 0, useBanglaDigits: false, unitLabel: 'meters')}',
                ),
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

  Future<void> _startPolygonDrawing(GeofenceMapController controller) async {
    Scaffold.maybeOf(context)?.closeDrawer();
    controller.highlightPolygon(null);

    final initialCenter =
        controller.currentLocation ??
        controller.primaryCenter ??
        controller.fallbackCenter;

    final userPolygon = await Navigator.of(context).push<UserPolygon>(
      MaterialPageRoute(
        builder: (context) => DrawPolygonPage(
          initialCenter: initialCenter,
          tileUrlTemplate: _selectedBaseLayer.urlTemplate,
          tileSubdomains: _selectedBaseLayer.subdomains,
        ),
      ),
    );

    if (!mounted || userPolygon == null) {
      return;
    }

    await controller.addUserPolygon(userPolygon);
    if (!mounted) {
      return;
    }

    final targetId = 'user_${userPolygon.id}';
    PolygonFeature? createdFeature;
    for (final polygon in controller.polygons) {
      if (polygon.id == targetId) {
        createdFeature = polygon;
        break;
      }
    }

    final displayName = userPolygon.name;
    if (createdFeature != null) {
      controller.highlightPolygon(createdFeature);
      final centroid = polygonCentroid(createdFeature);
      if (centroid != null) {
        controller.moveMap(centroid, 16);
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$displayName" পলিগন সংরক্ষণ করা হয়েছে।')),
    );
  }

  Future<void> _toggleTracking(GeofenceMapController controller) async {
    if (controller.isTracking) {
      controller.stopTracking();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ট্র্যাকিং বন্ধ করা হয়েছে।')),
      );
      return;
    }

    final started = await controller.startTracking();
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('বর্তমান অবস্থান না পাওয়া পর্যন্ত অপেক্ষা করুন।'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('🚶 ট্র্যাকিং শুরু হয়েছে।')));
  }

  List<Marker> _buildCustomPlaceMarkers(GeofenceMapController controller) {
    if (controller.customPlaces.isEmpty) {
      return const [];
    }

    final scale = _markerScaleForZoom(_currentZoom);
    final markerWidth = _customPlaceMarkerBaseWidth * scale;
    final markerHeight = _customPlaceMarkerBaseHeight * scale;

    return controller.customPlaces
        .map(
          (place) => Marker(
            point: place.location,
            width: markerWidth,
            height: markerHeight,
            alignment: Alignment.bottomCenter,
            child: CustomPlaceMarker(
              place: place,
              onTap: () => _showCustomPlaceDetails(controller, place),
              scale: scale,
              isSelected: identical(place, _selectedCustomPlace),
            ),
          ),
        )
        .toList();
  }

  double _markerScaleForZoom(double zoom) {
    const double minZoom = _customPlaceMarkerZoomThreshold;
    const double maxZoom = 18;
    const double minScale = 0.6;
    const double maxScale = 1.0;

    if (zoom <= minZoom) {
      return minScale;
    }
    if (zoom >= maxZoom) {
      return maxScale;
    }

    final interpolationFactor = (zoom - minZoom) / (maxZoom - minZoom);
    return minScale + (maxScale - minScale) * interpolationFactor;
  }

  Future<void> _goToCurrentLocation(GeofenceMapController controller) async {
    final location = controller.currentLocation;
    if (location != null) {
      controller.moveMap(location, defaultFollowZoom);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('বর্তমান অবস্থান এখনও পাওয়া যায়নি।')),
    );
  }

  String _polygonDisplayName(PolygonFeature polygon) {
    final plotNumber = polygon.properties['plot_number'];
    if (!isNullOrEmpty(plotNumber)) {
      return 'প্লট ${formatPropertyValue(plotNumber)}';
    }

    final name = polygon.properties['name'];
    if (!isNullOrEmpty(name)) {
      return formatPropertyValue(name);
    }

    final ward = polygon.properties['ward'];
    final block = polygon.properties['block'];
    if (!isNullOrEmpty(ward) && !isNullOrEmpty(block)) {
      final wardText = formatPropertyValue(ward);
      final blockText = formatPropertyValue(block);
      return '$wardText – $blockText';
    }
    if (!isNullOrEmpty(ward)) {
      return 'ওয়ার্ড ${formatPropertyValue(ward)}';
    }

    return 'পলিগন ${polygon.id.replaceAll('_', ' ')}';
  }

  Future<void> _startAddPlaceFlow(GeofenceMapController controller) async {
    final result = await Navigator.of(context).push<CustomPlace>(
      MaterialPageRoute(
        builder: (context) => AddPlacePage(
          initialLocation:
              controller.currentLocation ?? controller.fallbackCenter,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    await controller.addCustomPlace(result);

    if (!mounted) return;
    final displayName = result.name.isEmpty ? 'New place' : result.name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📍 "$displayName" added to the map.')),
    );
  }

  Future<void> _showCustomPlaceDetails(
    GeofenceMapController controller,
    CustomPlace place,
  ) async {
    final displayName = place.name.isEmpty ? 'Unnamed place' : place.name;
    setState(() {
      _selectedCustomPlace = place;
    });

    final action = await showModalBottomSheet<_PlaceDetailsAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => PlaceDetailsSheet(
        place: place,
        onEdit: () => Navigator.of(context).pop(_PlaceDetailsAction.edit),
        onDelete: () => Navigator.of(context).pop(_PlaceDetailsAction.delete),
      ),
    );

    if (!mounted) return;
    setState(() {
      _selectedCustomPlace = null;
    });

    if (action == _PlaceDetailsAction.delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('স্থান মুছে ফেলবেন?'),
            content: Text(
              'আপনি কি নিশ্চিত যে "$displayName" স্থানটি মানচিত্র থেকে মুছে ফেলতে চান?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('বাতিল'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('মুছে ফেলুন'),
              ),
            ],
          );
        },
      );

      if (confirmed == true) {
        await controller.removeCustomPlace(place);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📍 "$displayName" মুছে ফেলা হয়েছে।')),
        );
      }
      return;
    }

    if (action == _PlaceDetailsAction.edit) {
      final updatedPlace = await Navigator.of(context).push<CustomPlace>(
        MaterialPageRoute(
          builder: (context) => AddPlacePage(
            initialLocation: place.location,
            existingPlace: place,
          ),
        ),
      );

      if (updatedPlace != null) {
        await controller.updateCustomPlace(place, updatedPlace);
        if (!mounted) return;
        final updatedName = updatedPlace.name.isEmpty
            ? displayName
            : updatedPlace.name;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📍 "$updatedName" হালনাগাদ হয়েছে।')),
        );
        controller.moveMap(updatedPlace.location, defaultFollowZoom);
      }
    }
  }

  Future<void> _showLanguageSelector(AppLanguage currentLanguage) async {
    final selected = await showModalBottomSheet<AppLanguage>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _text(
                    currentLanguage,
                    'অ্যাপের ভাষা নির্বাচন করুন',
                    'Choose app language',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ...AppLanguage.values.map(
                  (option) => RadioListTile<AppLanguage>(
                    value: option,
                    groupValue: currentLanguage,
                    onChanged: (_) => Navigator.of(context).pop(option),
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.displayName),
                    subtitle:
                        Text(_languageOptionSubtitle(currentLanguage, option)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == currentLanguage) {
      return;
    }

    context.read<LanguageController>().setLanguage(selected);
  }

  Future<void> _showLayerSelector(AppLanguage language) async {
    final selected = await showModalBottomSheet<_MapLayerType>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _text(language, 'মানচিত্র ধরন', 'Map type'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _baseLayerOptions.length,
                  itemBuilder: (context, index) {
                    final option = _baseLayerOptions[index];
                    final isSelected = option.type == _selectedLayerType;
                    return _LayerOptionTile(
                      language: language,
                      option: option,
                      selected: isSelected,
                      onTap: () => Navigator.of(context).pop(option.type),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == _selectedLayerType) {
      return;
    }

    setState(() {
      _selectedLayerType = selected;
    });

    final option = _baseLayerOptions.firstWhere(
      (layer) => layer.type == selected,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _text(
            context.read<LanguageController>().language,
            'লেয়ার "${option.label}" নির্বাচিত হয়েছে।',
            'Layer "${option.label}" selected.',
          ),
        ),
      ),
    );
  }

  Future<void> _showPolygonDetails(
    GeofenceMapController controller,
    PolygonFeature polygon,
  ) async {
    controller.highlightPolygon(polygon);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => PolygonDetailsSheet(polygon: polygon),
    );
    controller.highlightPolygon(null);
  }

  Future<void> _showCurrentLocationDetails(
    GeofenceMapController controller,
  ) async {
    final language = context.read<LanguageController>().language;
    final useBanglaDigits = language.isBangla;
    if (!mounted) return;
    final location = controller.currentLocation;
    if (location == null) {
      return;
    }
    final accuracyValue = controller.currentAccuracy;
    final accuracyText = accuracyValue != null
        ? formatMeters(
            accuracyValue,
            fractionDigits: 1,
            useBanglaDigits: useBanglaDigits,
            unitLabel: useBanglaDigits ? 'মিটার' : 'meters',
          )
        : _text(language, 'উপলব্ধ নয়', 'Not available');
    final insideText = _text(
      language,
      controller.insideTarget
          ? 'আপনি নির্ধারিত এলাকায় আছেন'
          : 'আপনি নির্ধারিত এলাকায় নেই',
      controller.insideTarget
          ? 'You are inside the designated area'
          : 'You are outside the designated area',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _text(language, 'আপনার বর্তমান অবস্থান', 'Your current location'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  language,
                  'অক্ষাংশ: ${formatCoordinate(location.latitude)}',
                  'Latitude: ${formatCoordinate(location.latitude, useBanglaDigits: false)}',
                ),
              ),
              Text(
                _text(
                  language,
                  'দ্রাঘিমাংশ: ${formatCoordinate(location.longitude)}',
                  'Longitude: ${formatCoordinate(location.longitude, useBanglaDigits: false)}',
                ),
              ),
              Text(
                _text(
                  language,
                  'সঠিকতা: $accuracyText',
                  'Accuracy: $accuracyText',
                ),
              ),
              Text(insideText),
              const SizedBox(height: 8),
              Text(
                _text(
                  language,
                  'সর্বশেষ আপডেট: ${formatTimestampBangla(DateTime.now().millisecondsSinceEpoch)}',
                  'Last updated: ${formatTimestampLocalized(DateTime.now().millisecondsSinceEpoch, useBanglaDigits: false)}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_text(language, 'বন্ধ করুন', 'Close')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showHistoryEntryDetails(LocationHistoryEntry entry) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('সংরক্ষিত অবস্থান'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('অক্ষাংশ: ${formatCoordinate(entry.latitude)}'),
              Text('দ্রাঘিমাংশ: ${formatCoordinate(entry.longitude)}'),
              Text(
                'সঠিকতা: ${formatMeters(entry.accuracy, fractionDigits: 1)}',
              ),
              Text('নির্ধারিত সীমানার ভেতরে: ${entry.inside ? 'হ্যাঁ' : 'না'}'),
              Text('সময়: ${formatTimestampBangla(entry.timestampMs)}'),
            ],
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
}

class _MapSidebar extends StatelessWidget {
  const _MapSidebar({
    required this.controller,
    required this.isTracking,
    required this.language,
    required this.onAddPlace,
    required this.onAddPolygon,
    required this.onToggleTracking,
    required this.onCalibrate,
    required this.onMouzaSelectionChanged,
    required this.onSelectAllMouzas,
    required this.onClearMouzas,
    required this.onToggleBoundary,
    required this.onToggleOtherPolygons,
  });

  final GeofenceMapController controller;
  final bool isTracking;
  final AppLanguage language;
  final VoidCallback onAddPlace;
  final VoidCallback onAddPolygon;
  final VoidCallback? onToggleTracking;
  final VoidCallback? onCalibrate;
  final ValueChanged<Set<String>> onMouzaSelectionChanged;
  final VoidCallback onSelectAllMouzas;
  final VoidCallback onClearMouzas;
  final ValueChanged<bool> onToggleBoundary;
  final ValueChanged<bool> onToggleOtherPolygons;

  static const List<String> _balumohalInformationItems = <String>[
    'ড্রেজারের লোকেশন',
    'হাইড্রোগ্রাফিক জরিপ',
    'ইজারা সংক্রান্ত বিজ্ঞপ্তি',
  ];

  static const List<String> _otherInformationButtons = <String>['জলমহাল সমূহ'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mouzas = controller.availableMouzaNames;
    final selectedMouzas = controller.selectedMouzaNames;
    String _text(String bangla, String english) =>
        language.isBangla ? bangla : english;
    final controls = <Widget>[
      FilledButton.icon(
        onPressed: onAddPlace,
        icon: const Icon(Icons.add_location_alt),
        label: Text(_text('নতুন স্থান যুক্ত করুন', 'Add new place')),
      ),
      FilledButton.icon(
        onPressed: onAddPolygon,
        icon: const Icon(Icons.format_shapes),
        label: Text(_text('নতুন পলিগন আঁকুন', 'Draw new polygon')),
      ),
      FilledButton.icon(
        onPressed: onToggleTracking,
        icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
        label: Text(
          isTracking
              ? _text('ট্র্যাকিং বন্ধ করুন', 'Stop tracking')
              : _text('ট্র্যাকিং শুরু করুন', 'Start tracking'),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: isTracking ? Colors.redAccent : null,
        ),
      ),
      FilledButton.tonalIcon(
        onPressed: onCalibrate,
        icon: const Icon(Icons.compass_calibration),
        label: Text(_text('ক্যালিব্রেট করুন', 'Calibrate')),
      ),
    ];

    return Material(
      elevation: 4,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.95),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _text('মানচিত্র নিয়ন্ত্রণ', 'Map controls'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (int i = 0; i < controls.length; i++) ...[
                    if (i != 0) const SizedBox(height: 8),
                    controls[i],
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  //Text('লেয়ার দৃশ্যমানতা', style: theme.textTheme.titleMedium),
                  // SwitchListTile(
                  //   value: controller.showBoundary,
                  //   onChanged: onToggleBoundary,
                  //   title: const Text('শীট বাউন্ডারি দেখান'),
                  //   dense: true,
                  //   contentPadding: EdgeInsets.zero,
                  // ),
                  // SwitchListTile(
                  //   value: controller.showOtherPolygons,
                  //   onChanged: onToggleOtherPolygons,
                  //   title: const Text('অন্যান্য পলিগন দেখান'),
                  //   dense: true,
                  //   contentPadding: EdgeInsets.zero,
                  // ),
                  const SizedBox(height: 16),
                  Text(
                    _text('তথ্য সেবা', 'Information services'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _CollapsibleInformationButton(
                    title: _text('বালুমহাল সমূহ', 'Balu Mohal resources'),
                    items: _balumohalInformationItems,
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _otherInformationButtons.length; i++) ...[
                    if (i != 0) const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () {},
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          language.isBangla
                              ? _otherInformationButtons[i]
                              : 'Waterbody resources',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    _text('মৌজা নির্বাচন করুন', 'Select mouzas'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(_text('মৌজা', 'Mouza')),
                      children: [
                        SwitchListTile(
                          value: controller.showBoundary,
                          onChanged: onToggleBoundary,
                          title: Text(
                            _text('শীট বাউন্ডারি দেখান', 'Show sheet boundary'),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (mouzas.isEmpty)
                          Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _text(
                                  'কোনও মৌজা তথ্য পাওয়া যায়নি।',
                                  'No mouza data available.',
                                ),
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed:
                                          selectedMouzas.length == mouzas.length
                                          ? null
                                          : onSelectAllMouzas,
                                      icon: const Icon(Icons.select_all),
                                      label: Text(
                                        _text('সব নির্বাচন করুন', 'Select all'),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: selectedMouzas.isEmpty
                                          ? null
                                          : onClearMouzas,
                                      icon: const Icon(Icons.clear_all),
                                      label: Text(
                                        _text(
                                          'সব অপসারণ করুন',
                                          'Clear selection',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ...mouzas.map(
                                  (mouza) => CheckboxListTile(
                                    value: selectedMouzas.contains(mouza),
                                    title: Text(_formatMouzaName(mouza)),
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (checked) {
                                      final next = selectedMouzas.toSet();
                                      if (checked ?? false) {
                                        next.add(mouza);
                                      } else {
                                        next.remove(mouza);
                                      }
                                      onMouzaSelectionChanged(next);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('assets/gmgi_logo_trans.png', height: 28),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Copyright © Developed by GMGI Solutions Ltd.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMouzaName(String value) {
    return value.replaceAll('_', ' ');
  }
}

class _CollapsibleInformationButton extends StatelessWidget {
  const _CollapsibleInformationButton({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: theme.colorScheme.primary,
          collapsedIconColor: theme.colorScheme.primary,
          title: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            for (int i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 8 : 12),
                child: FilledButton.tonal(
                  onPressed: () {},
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(items[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PlaceDetailsAction { edit, delete }

class _LanguageControlButton extends StatelessWidget {
  const _LanguageControlButton({
    required this.language,
    required this.tooltip,
    required this.onPressed,
  });

  final AppLanguage language;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.surfaceVariant.withOpacity(0.9),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  language.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LayerControlButton extends StatelessWidget {
  const _LayerControlButton({required this.onPressed});

  //final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.9),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers_outlined, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayerOptionTile extends StatelessWidget {
  const _LayerOptionTile({
    required this.language,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final _BaseLayerOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = option.label(language);
    final subtitle = option.subtitle(language);
    final borderColor = selected
        ? theme.colorScheme.primary
        : Colors.transparent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    option.type == _MapLayerType.satellite
                        ? const Color(0xFF90CAF9)
                        : const Color(0xFFB3E5FC),
                    option.type == _MapLayerType.terrain
                        ? const Color(0xFFC8E6C9)
                        : const Color(0xFFE1F5FE),
                  ],
                ),
                border: Border.all(color: borderColor, width: selected ? 2 : 1),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      option.type == _MapLayerType.satellite
                          ? Icons.public
                          : option.type == _MapLayerType.terrain
                          ? Icons.terrain
                          : Icons.map,
                      size: 36,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.language,
    required this.collapsed,
    required this.onToggle,
    required this.accuracyText,
    required this.statusMessage,
    this.errorMessage,
  });

  final AppLanguage language;
  final bool collapsed;
  final VoidCallback onToggle;
  final String accuracyText;
  final String statusMessage;
  final String? errorMessage;

  String _text(String bangla, String english) {
    return language.isBangla ? bangla : english;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface.withOpacity(0.95);
    final borderRadius = BorderRadius.circular(18);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: collapsed
          ? Material(
              key: const ValueKey('collapsed_status_panel'),
              elevation: 6,
              borderRadius: borderRadius,
              color: surfaceColor,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.gps_fixed, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _text('জিপিএস তথ্য', 'GPS information'),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _text(
                              'সঠিকতা: $accuracyText',
                              'Accuracy: $accuracyText',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                ),
              ),
            )
          : Material(
              key: const ValueKey('expanded_status_panel'),
              elevation: 8,
              borderRadius: borderRadius,
              color: surfaceColor,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: onToggle,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.gps_fixed,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _text('জিপিএস তথ্য', 'GPS information'),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_up),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _text('জিপিএস এর অবস্থা', 'GPS status'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _text(
                          'সঠিকতা: $accuracyText',
                          'Accuracy: $accuracyText',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(statusMessage),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: language.isBangla
                                ? Colors.red
                                : theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
