import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:balumohol/core/utils/formatting.dart';
import 'package:balumohol/features/geofence/constants.dart';
import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/models/location_history_entry.dart';
import 'package:balumohol/features/geofence/models/polygon_feature.dart';
import 'package:balumohol/features/geofence/models/user_polygon.dart';
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

class _PolygonColorOption {
  const _PolygonColorOption(this.label, this.color);

  final String label;
  final Color color;
}

const List<_PolygonColorOption> _polygonColorOptions = <_PolygonColorOption>[
  _PolygonColorOption('নীল', Color(0xFF1976D2)),
  _PolygonColorOption('সবুজ', Color(0xFF2E7D32)),
  _PolygonColorOption('কমলা', Color(0xFFEF6C00)),
  _PolygonColorOption('বেগুনি', Color(0xFF6A1B9A)),
  _PolygonColorOption('লাল', Color(0xFFC62828)),
];

class _NewPolygonDetails {
  const _NewPolygonDetails({
    required this.name,
    required this.color,
  });

  final String name;
  final Color color;
}

class _GeofenceMapPageState extends State<GeofenceMapPage> {
  static const double _customPlaceMarkerZoomThreshold = 14;
  static const double _customPlaceMarkerBaseWidth = 160;
  static const double _customPlaceMarkerBaseHeight = 64;

  bool _initialised = false;
  double _currentZoom = 15;
  CustomPlace? _selectedCustomPlace;
  bool _statusPanelCollapsed = true;
  _MapLayerType _selectedLayerType = _MapLayerType.hybrid;
  bool _isDrawingPolygon = false;
  final List<LatLng> _draftPolygonPoints = <LatLng>[];

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
    final polygonLabelMarkers = _buildPolygonLabels(controller);
    final draftMarkers =
        _isDrawingPolygon ? _buildDraftPolygonMarkers() : const <Marker>[];
    final draftPoints = List<LatLng>.from(_draftPolygonPoints);
    final bool isDrawingPolygon = _isDrawingPolygon;
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
          onAddPolygon: () => _startPolygonDrawing(controller),
          onToggleTracking: trackingCallback,
          onCalibrate: calibrateCallback,
          onShowLayerSelector: _showLayerSelector,
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
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'navigate_btn',
              onPressed: controller.centerOnPrimaryArea,
              icon: const Icon(Icons.layers),
              label: const Text('বালুমহাল'),
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
                if (_isDrawingPolygon) {
                  setState(() {
                    _draftPolygonPoints.add(point);
                  });
                  return;
                }
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
              if (isDrawingPolygon && draftPoints.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: draftPoints,
                      color: Colors.deepOrangeAccent.withOpacity(0.2),
                      borderColor: Colors.deepOrangeAccent,
                      borderStrokeWidth: 3,
                      isFilled: true,
                    ),
                  ],
                ),
              if (isDrawingPolygon && draftPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        ...draftPoints,
                        if (draftPoints.length >= 3) draftPoints.first,
                      ],
                      strokeWidth: 3,
                      color: Colors.deepOrangeAccent,
                    ),
                  ],
                ),
              if (isDrawingPolygon && draftMarkers.isNotEmpty)
                MarkerLayer(markers: draftMarkers),
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
          if (isDrawingPolygon)
            _buildPolygonDrawingOverlay(controller, draftPoints.length),
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
    return controller.polygons.where((polygon) => polygon.outer.isNotEmpty).map(
      (polygon) {
        final bool isSelected = polygon.id == selectedId;
        final customColor = _customPolygonColor(polygon.properties);
        final Color fillColor;
        final Color borderColor;
        if (customColor != null) {
          fillColor = customColor.withOpacity(isSelected ? 0.45 : 0.28);
          borderColor = customColor;
        } else {
          fillColor =
              isSelected ? polygonSelectedFillColor : polygonBaseFillColor;
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
      },
    ).toList();
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
    final polygons = controller.polygons;
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
      final backgroundColor = customColor != null
          ? customColor.withOpacity(isSelected ? 0.9 : 0.75)
          : Colors.black.withOpacity(isSelected ? 0.85 : 0.7);
      final textColor =
          backgroundColor.computeLuminance() > 0.6 ? Colors.black : Colors.white;
      markers.add(
        Marker(
          point: centroid,
          width: 220,
          height: 60,
          alignment: Alignment.center,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final textStyle = theme.textTheme.labelMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ) ??
                  TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  );
              return IgnorePointer(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.85),
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
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
                ),
              );
            },
          ),
        ),
      );
    }
    return markers;
  }

  List<Marker> _buildDraftPolygonMarkers() {
    return List<Marker>.generate(
      _draftPolygonPoints.length,
      (index) {
        final point = _draftPolygonPoints[index];
        return Marker(
          point: point,
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final textStyle = theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ) ??
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  );
              return IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.deepOrangeAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text('${index + 1}', style: textStyle),
                ),
              );
            },
          ),
        );
      },
    );
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

  void _startPolygonDrawing(GeofenceMapController controller) {
    if (_isDrawingPolygon) {
      return;
    }
    Scaffold.maybeOf(context)?.closeDrawer();
    setState(() {
      _isDrawingPolygon = true;
      _draftPolygonPoints.clear();
    });
    controller.highlightPolygon(null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('নতুন পলিগন আঁকার জন্য মানচিত্রে পয়েন্ট ট্যাপ করুন।'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _cancelPolygonDrawing() {
    if (!_isDrawingPolygon) {
      return;
    }
    setState(() {
      _isDrawingPolygon = false;
      _draftPolygonPoints.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('পলিগন আঁকা বাতিল করা হয়েছে।')),
    );
  }

  void _undoPolygonPoint() {
    if (_draftPolygonPoints.isEmpty) {
      return;
    }
    setState(() {
      _draftPolygonPoints.removeLast();
    });
  }

  Future<void> _finishPolygonDrawing(GeofenceMapController controller) async {
    if (_draftPolygonPoints.length < 3) {
      return;
    }
    final details = await _promptForPolygonDetails();
    if (!mounted || details == null) {
      return;
    }

    final trimmedName = details.name.trim();
    final displayName =
        trimmedName.isEmpty ? 'কাস্টম পলিগন' : trimmedName;

    final userPolygon = UserPolygon(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: displayName,
      colorValue: details.color.value,
      points: List<LatLng>.from(_draftPolygonPoints),
    );

    await controller.addUserPolygon(userPolygon);
    if (!mounted) {
      return;
    }

    setState(() {
      _isDrawingPolygon = false;
      _draftPolygonPoints.clear();
    });

    final targetId = 'user_${userPolygon.id}';
    PolygonFeature? createdFeature;
    for (final polygon in controller.polygons) {
      if (polygon.id == targetId) {
        createdFeature = polygon;
        break;
      }
    }

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

  Future<_NewPolygonDetails?> _promptForPolygonDetails() async {
    final nameController = TextEditingController();
    Color selectedColor = _polygonColorOptions.first.color;
    try {
      return showDialog<_NewPolygonDetails>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              final theme = Theme.of(context);
              return AlertDialog(
                title: const Text('পলিগনের বিস্তারিত'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'নাম',
                          hintText: 'পলিগনের নাম লিখুন',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'রং নির্বাচন করুন',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final option in _polygonColorOptions)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => setState(
                                  () => selectedColor = option.color,
                                ),
                                borderRadius: BorderRadius.circular(28),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: _PolygonColorPreview(
                                    color: option.color,
                                    label: option.label,
                                    selected: selectedColor == option.color,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('বাতিল'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _NewPolygonDetails(
                          name: nameController.text,
                          color: selectedColor,
                        ),
                      );
                    },
                    child: const Text('সংরক্ষণ করুন'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
    }
  }

  Widget _buildPolygonDrawingOverlay(
    GeofenceMapController controller,
    int pointCount,
  ) {
    final theme = Theme.of(context);
    final instructionText = pointCount >= 3
        ? 'সংরক্ষণ করতে "সংরক্ষণ করুন" চাপুন।'
        : 'কমপক্ষে ৩টি পয়েন্ট প্রয়োজন।';
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surface.withOpacity(0.95),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'নতুন পলিগন আঁকা হচ্ছে',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'মানচিত্রে ট্যাপ করে পয়েন্ট যোগ করুন। $instructionText',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: pointCount > 0 ? _undoPolygonPoint : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('আনডু'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _cancelPolygonDrawing,
                    icon: const Icon(Icons.close),
                    label: const Text('বাতিল'),
                  ),
                  FilledButton.icon(
                    onPressed: pointCount >= 3
                        ? () => _finishPolygonDrawing(controller)
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('সংরক্ষণ করুন'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    required this.onAddPolygon,
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
  final VoidCallback onAddPolygon;
  final VoidCallback? onToggleTracking;
  final VoidCallback? onCalibrate;
  final VoidCallback onShowLayerSelector;
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

  static const List<String> _otherInformationButtons = <String>[
    'জলমহাল সমূহ',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mouzas = controller.availableMouzaNames;
    final selectedMouzas = controller.selectedMouzaNames;
    final controls = <Widget>[
      FilledButton.icon(
        onPressed: onAddPlace,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('নতুন স্থান যুক্ত করুন'),
      ),
      FilledButton.icon(
        onPressed: onAddPolygon,
        icon: const Icon(Icons.format_shapes),
        label: const Text('নতুন পলিগন আঁকুন'),
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
        label: const Text('ক্যালিব্রেট করুন'),
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
                  Text('তথ্য সেবা', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _CollapsibleInformationButton(
                    title: 'বালুমহাল সমূহ',
                    items: _balumohalInformationItems,
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _otherInformationButtons.length; i++) ...[
                    if (i != 0) const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () {},
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_otherInformationButtons[i]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'মৌজা নির্বাচন করুন',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: const Text('মৌজা'),
                      children: [
                        SwitchListTile(
                          value: controller.showBoundary,
                          onChanged: onToggleBoundary,
                          title: const Text('শীট বাউন্ডারি দেখান'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (mouzas.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('কোনও মৌজা তথ্য পাওয়া যায়নি।'),
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

class _PolygonColorPreview extends StatelessWidget {
  const _PolygonColorPreview({
    required this.color,
    required this.label,
    required this.selected,
  });

  final Color color;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double size = selected ? 48 : 44;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface.withOpacity(0.9)
                  : Colors.white,
              width: selected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(selected ? 0.45 : 0.3),
                blurRadius: selected ? 10 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
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
