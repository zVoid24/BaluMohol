import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:balumohol/core/utils/formatting.dart';
import 'package:balumohol/features/geofence/constants.dart';
import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/models/location_history_entry.dart';
import 'package:balumohol/features/geofence/models/polygon_feature.dart';
import 'package:balumohol/features/geofence/presentation/widgets/current_location_indicator.dart';
import 'package:balumohol/features/geofence/presentation/widgets/custom_place_marker.dart';
import 'package:balumohol/features/geofence/presentation/widgets/place_details_sheet.dart';
import 'package:balumohol/features/geofence/presentation/widgets/polygon_details_sheet.dart';
import 'package:balumohol/features/geofence/providers/geofence_map_controller.dart';
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
    required this.label,
    required this.urlTemplate,
    this.subdomains,
    this.subtitle,
  });

  final _MapLayerType type;
  final String label;
  final String urlTemplate;
  final List<String>? subdomains;
  final String? subtitle;
}

const List<String> _googleSubdomains = <String>['mt0', 'mt1', 'mt2', 'mt3'];

const List<_BaseLayerOption> _baseLayerOptions = <_BaseLayerOption>[
  _BaseLayerOption(
    type: _MapLayerType.hybrid,
    label: 'হাইব্রিড',
    subtitle: 'স্যাটেলাইট ছবি ও মানচিত্র লেবেল',
    urlTemplate: 'https://{s}.google.com/vt/lyrs=s,h&x={x}&y={y}&z={z}',
    subdomains: _googleSubdomains,
  ),
  _BaseLayerOption(
    type: _MapLayerType.satellite,
    label: 'স্যাটেলাইট',
    subtitle: 'শুধু স্যাটেলাইট ছবি',
    urlTemplate: 'https://{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
    subdomains: _googleSubdomains,
  ),
  _BaseLayerOption(
    type: _MapLayerType.terrain,
    label: 'টেরেইন',
    subtitle: 'ভূপ্রকৃতি ও উচ্চতার মানচিত্র',
    urlTemplate: 'https://{s}.google.com/vt/lyrs=p&x={x}&y={y}&z={z}',
    subdomains: _googleSubdomains,
  ),
  _BaseLayerOption(
    type: _MapLayerType.roadmap,
    label: 'স্ট্যান্ডার্ড মানচিত্র',
    subtitle: 'সাধারণ রাস্তা ও স্থান',
    urlTemplate: 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
    subdomains: _googleSubdomains,
  ),
  _BaseLayerOption(
    type: _MapLayerType.osm,
    label: 'ওপেনস্ট্রিটম্যাপ',
    subtitle: 'ওপেন সোর্স কমিউনিটি মানচিত্র',
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
    final currentMarker = _buildCurrentLocationMarker(controller);
    final historyMarkers = _buildHistoryMarkers(controller);
    final customPlaceMarkers = _showCustomPlaceMarkers
        ? _buildCustomPlaceMarkers(controller)
        : <Marker>[];
    final pathPoints = controller.trackingPath;
    final accuracyValue = controller.currentAccuracy;
    final accuracyText = accuracyValue != null
        ? formatMeters(accuracyValue, fractionDigits: 0)
        : 'অপেক্ষা চলছে...';
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
          onAddPlace: () => _startAddPlaceFlow(controller),
          onToggleTracking: trackingCallback,
          onCalibrate: calibrateCallback,
          onShowLayerSelector: _showLayerSelector,
          onMouzaSelectionChanged:
              (selection) => controller.setSelectedMouzas(selection),
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
              tooltip: 'বর্তমান অবস্থানে যান',
              child: const Icon(Icons.my_location),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'compass_btn',
              onPressed: controller.resetRotation,
              tooltip: 'মানচিত্র উত্তরের দিকে ঘোরান',
              child: const Icon(Icons.explore),
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
                subdomains:
                    _selectedBaseLayer.subdomains ?? const <String>[],
                userAgentPackageName: 'com.example.balumohol',
              ),
              if (controller.polygons.isNotEmpty)
                PolygonLayer(polygons: _buildPolygons(controller)),
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
              if (currentMarker != null)
                MarkerLayer(markers: [currentMarker]),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topRight,
                child: _StatusPanel(
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
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(0.9),
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
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: controller.centerOnPrimaryArea,
                  child: const Text('বালুমহাল'),
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
    return controller.polygons.where((polygon) => polygon.outer.isNotEmpty).map(
      (polygon) {
        final bool isSelected = polygon.id == selectedId;
        return Polygon(
          points: polygon.outer,
          holePointsList: polygon.holes,
          color: isSelected ? polygonSelectedFillColor : polygonBaseFillColor,
          borderColor: isSelected
              ? polygonSelectedBorderColor
              : polygonBaseBorderColor,
          borderStrokeWidth: isSelected ? 3.6 : 2.8,
          isFilled: true,
        );
      },
    ).toList();
  }

  Marker? _buildCurrentLocationMarker(GeofenceMapController controller) {
    final location = controller.currentLocation;
    if (location == null) {
      return null;
    }
    final accuracyValue = controller.currentAccuracy;
    final accuracyText = accuracyValue != null
        ? formatMeters(accuracyValue, fractionDigits: 0)
        : 'উপলব্ধ নয়';
    return Marker(
      point: location,
      width: 48,
      height: 48,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () => _showCurrentLocationDetails(controller),
        child: Tooltip(
          message: 'আপনি এখানে আছেন\nসঠিকতা: $accuracyText',
          child: CurrentLocationIndicator(heading: controller.currentHeading),
        ),
      ),
    );
  }

  List<Marker> _buildHistoryMarkers(GeofenceMapController controller) {
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
                message:
                    'সময়: ${formatTimestampBangla(entry.timestampMs)}\nলক্ষ্য এলাকায় আছেন: ${entry.inside ? 'হ্যাঁ' : 'না'}\nসঠিকতা: ${formatMeters(entry.accuracy, fractionDigits: 0)}',
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

  Future<void> _showLayerSelector() async {
    final selected = await showModalBottomSheet<_MapLayerType>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.7;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text(
                      'একটি লেয়ার নির্বাচন করুন',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Divider(height: 0),
                  ..._baseLayerOptions.map(
                    (option) => RadioListTile<_MapLayerType>(
                      value: option.type,
                      groupValue: _selectedLayerType,
                      title: Text(option.label),
                      subtitle: option.subtitle != null
                          ? Text(option.subtitle!)
                          : null,
                      onChanged: (value) =>
                          Navigator.of(context).pop(option.type),
                    ),
                  ),
                ],
              ),
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
      SnackBar(content: Text('লেয়ার "${option.label}" নির্বাচিত হয়েছে।')),
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
    if (!mounted) return;
    final location = controller.currentLocation;
    if (location == null) {
      return;
    }
    final accuracyValue = controller.currentAccuracy;
    final accuracyText = accuracyValue != null
        ? formatMeters(accuracyValue, fractionDigits: 1)
        : 'উপলব্ধ নয়';
    final insideText = controller.insideTarget
        ? 'আপনি নির্ধারিত এলাকায় আছেন'
        : 'আপনি নির্ধারিত এলাকায় নেই';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('আপনার বর্তমান অবস্থান'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('অক্ষাংশ: ${formatCoordinate(location.latitude)}'),
              Text('দ্রাঘিমাংশ: ${formatCoordinate(location.longitude)}'),
              Text('সঠিকতা: $accuracyText'),
              Text(insideText),
              const SizedBox(height: 8),
              Text(
                'সর্বশেষ আপডেট: ${formatTimestampBangla(DateTime.now().millisecondsSinceEpoch)}',
              ),
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
    required this.onAddPlace,
    required this.onToggleTracking,
    required this.onCalibrate,
    required this.onShowLayerSelector,
    required this.onMouzaSelectionChanged,
    required this.onSelectAllMouzas,
    required this.onClearMouzas,
    required this.onToggleBoundary,
    required this.onToggleOtherPolygons,
  });

  final GeofenceMapController controller;
  final bool isTracking;
  final VoidCallback onAddPlace;
  final VoidCallback? onToggleTracking;
  final VoidCallback? onCalibrate;
  final VoidCallback onShowLayerSelector;
  final ValueChanged<Set<String>> onMouzaSelectionChanged;
  final VoidCallback onSelectAllMouzas;
  final VoidCallback onClearMouzas;
  final ValueChanged<bool> onToggleBoundary;
  final ValueChanged<bool> onToggleOtherPolygons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mouzas = controller.availableMouzaNames;
    final selectedMouzas = controller.selectedMouzaNames;
    final controls = <Widget>[
      FilledButton.icon(
        onPressed: onAddPlace,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('জায়গা যোগ করুন'),
      ),
      FilledButton.icon(
        onPressed: onToggleTracking,
        icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
        label: Text(isTracking ? 'ট্র্যাকিং বন্ধ করুন' : 'ট্র্যাকিং শুরু করুন'),
        style: FilledButton.styleFrom(
          backgroundColor: isTracking ? Colors.redAccent : null,
        ),
      ),
      FilledButton.tonalIcon(
        onPressed: onCalibrate,
        icon: const Icon(Icons.compass_calibration),
        label: const Text('এখন ক্যালিব্রেট করুন'),
      ),
      OutlinedButton.icon(
        onPressed: onShowLayerSelector,
        icon: const Icon(Icons.layers_outlined),
        label: const Text('লেয়ার নির্বাচন করুন'),
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
                    'মানচিত্র নিয়ন্ত্রণ',
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
                  Text('লেয়ার দৃশ্যমানতা', style: theme.textTheme.titleMedium),
                  SwitchListTile(
                    value: controller.showBoundary,
                    onChanged: onToggleBoundary,
                    title: const Text('শীট বাউন্ডারি দেখান'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: controller.showOtherPolygons,
                    onChanged: onToggleOtherPolygons,
                    title: const Text('অন্যান্য পলিগন দেখান'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'মৌজা নির্বাচন করুন',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (mouzas.isEmpty)
                    const Text('কোনও মৌজা তথ্য পাওয়া যায়নি।')
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: selectedMouzas.length == mouzas.length
                              ? null
                              : onSelectAllMouzas,
                          icon: const Icon(Icons.select_all),
                          label: const Text('সব নির্বাচন করুন'),
                        ),
                        OutlinedButton.icon(
                          onPressed: selectedMouzas.isEmpty
                              ? null
                              : onClearMouzas,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('সব অপসারণ করুন'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...mouzas.map(
                      (mouza) => CheckboxListTile(
                        value: selectedMouzas.contains(mouza),
                        title: Text(_formatMouzaName(mouza)),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
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

enum _PlaceDetailsAction { edit, delete }

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.collapsed,
    required this.onToggle,
    required this.accuracyText,
    required this.statusMessage,
    this.errorMessage,
  });

  final bool collapsed;
  final VoidCallback onToggle;
  final String accuracyText;
  final String statusMessage;
  final String? errorMessage;

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
                            'জিপিএস তথ্য',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'সঠিকতা: $accuracyText',
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
                                  'জিপিএস তথ্য',
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
                        'জিপিএস এর অবস্থা',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('সঠিকতা: $accuracyText'),
                      const SizedBox(height: 4),
                      Text(statusMessage),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.red,
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
