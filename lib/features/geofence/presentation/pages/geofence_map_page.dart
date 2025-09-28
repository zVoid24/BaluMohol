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
import 'package:balumohol/features/geofence/presentation/widgets/status_card.dart';
import 'package:balumohol/features/geofence/providers/geofence_map_controller.dart';
import 'package:balumohol/features/places/presentation/pages/add_place_page.dart';

class GeofenceMapPage extends StatefulWidget {
  const GeofenceMapPage({super.key});

  @override
  State<GeofenceMapPage> createState() => _GeofenceMapPageState();
}

class _GeofenceMapPageState extends State<GeofenceMapPage> {
  static const double _customPlaceMarkerZoomThreshold = 14;
  static const double _customPlaceMarkerBaseWidth = 160;
  static const double _customPlaceMarkerBaseHeight = 64;

  bool _initialised = false;
  double _currentZoom = 15;

  bool get _showCustomPlaceMarkers =>
      _currentZoom >= _customPlaceMarkerZoomThreshold;

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
    final customPlaceMarkers =
        _showCustomPlaceMarkers ? _buildCustomPlaceMarkers(controller) : <Marker>[];

    final accuracyValue = controller.currentAccuracy;
    final accuracyText = accuracyValue != null
        ? formatMeters(accuracyValue, fractionDigits: 0)
        : 'অপেক্ষা চলছে...';

    return Scaffold(
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
            FloatingActionButton.extended(
              heroTag: 'calibrate_btn',
              onPressed:
                  controller.permissionDenied ? null : () => controller.calibrateNow(),
              label: const Text('এখন ক্যালিব্রেট করুন'),
              icon: const Icon(Icons.compass_calibration),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'add_place_btn',
              onPressed: () => _startAddPlaceFlow(controller),
              label: const Text('Add place'),
              icon: const Icon(Icons.add_location_alt),
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
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.balumohol',
              ),
              if (controller.polygons.isNotEmpty)
                PolygonLayer(polygons: _buildPolygons(controller)),
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
                child: StatusCard(
                  accuracyText: accuracyText,
                  statusMessage: controller.statusMessage,
                  errorMessage: controller.errorMessage,
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
    return controller.polygons
        .where((polygon) => polygon.outer.isNotEmpty)
        .map(
          (polygon) {
            final bool isSelected = polygon.id == selectedId;
            return Polygon(
              points: polygon.outer,
              holePointsList: polygon.holes,
              color: isSelected ? polygonSelectedFillColor : polygonBaseFillColor,
              borderColor:
                  isSelected ? polygonSelectedBorderColor : polygonBaseBorderColor,
              borderStrokeWidth: isSelected ? 3.6 : 2.8,
              isFilled: true,
            );
          },
        )
        .toList();
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
          child: const CurrentLocationIndicator(),
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
              onTap: () => _showCustomPlaceDetails(place),
              scale: scale,
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

  Future<void> _startAddPlaceFlow(GeofenceMapController controller) async {
    final result = await Navigator.of(context).push<CustomPlace>(
      MaterialPageRoute(
        builder: (context) => AddPlacePage(
          initialLocation: controller.currentLocation ?? controller.fallbackCenter,
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
      SnackBar(
        content: Text('📍 "$displayName" added to the map.'),
      ),
    );
  }

  Future<void> _showCustomPlaceDetails(CustomPlace place) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => PlaceDetailsSheet(place: place),
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
    final location = controller.currentLocation;
    if (location == null) {
      return;
    }
    final accuracyValue = controller.currentAccuracy;
    final accuracyText = accuracyValue != null
        ? formatMeters(accuracyValue, fractionDigits: 1)
        : 'উপলব্ধ নয়';
    final insideText = controller.insideTarget
        ? 'আপনি লক্ষ্য এলাকায় আছেন'
        : 'আপনি লক্ষ্য এলাকায় নেই';

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
              Text('সর্বশেষ আপডেট: ${formatTimestampBangla(DateTime.now().millisecondsSinceEpoch)}'),
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
              Text('সঠিকতা: ${formatMeters(entry.accuracy, fractionDigits: 1)}'),
              Text('লক্ষ্য সীমানার ভেতরে: ${entry.inside ? 'হ্যাঁ' : 'না'}'),
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
