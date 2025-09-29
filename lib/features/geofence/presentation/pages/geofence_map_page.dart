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

class _GeofenceMapPageState extends State<GeofenceMapPage> {
  static const double _customPlaceMarkerZoomThreshold = 14;
  static const double _customPlaceMarkerBaseWidth = 160;
  static const double _customPlaceMarkerBaseHeight = 64;

  bool _initialised = false;
  double _currentZoom = 15;
  CustomPlace? _selectedCustomPlace;
  final GlobalKey _polygonButtonKey = GlobalKey();
  bool _statusPanelCollapsed = true;

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
    final customPlaceMarkers = _showCustomPlaceMarkers
        ? _buildCustomPlaceMarkers(controller)
        : <Marker>[];
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
            FloatingActionButton(
              heroTag: 'compass_btn',
              onPressed: controller.resetRotation,
              tooltip: 'মানচিত্র উত্তরের দিকে ঘোরান',
              child: const Icon(Icons.explore),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              key: _polygonButtonKey,
              heroTag: 'polygon_btn',
              onPressed: () => _showPolygonSelector(controller),
              label: const Text('পলিগন'),
              icon: const Icon(Icons.layers),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'calibrate_btn',
              onPressed: controller.permissionDenied
                  ? null
                  : () => controller.calibrateNow(),
              label: const Text('এখন ক্যালিব্রেট করুন'),
              icon: const Icon(Icons.compass_calibration),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'add_place_btn',
              onPressed: () => _startAddPlaceFlow(controller),
              label: const Text('জায়গা যোগ করুন'),
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

  Future<void> _showPolygonSelector(GeofenceMapController controller) async {
    final polygons = controller.polygons;
    controller.focusPolygon(polygons[59], highlight: false);
    // //print(polygons);
    // if (polygons.isEmpty) {
    //   if (!mounted) return;
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(content: Text('কোনও পলিগন পাওয়া যায়নি।')),
    //   );
    //   return;
    // }

    // if (polygons.length == 1) {
    //   controller.focusPolygon(polygons.first);
    //   print(polygons.first);
    //   return;
    // }

    // final RenderBox? buttonBox =
    //     _polygonButtonKey.currentContext?.findRenderObject() as RenderBox?;
    // final OverlayState? overlayState = Overlay.of(context);
    // final RenderBox? overlayBox =
    //     overlayState?.context.findRenderObject() as RenderBox?;

    // PolygonFeature? selected;
    // if (buttonBox != null && overlayBox != null) {
    //   final Offset topLeft = buttonBox.localToGlobal(
    //     Offset.zero,
    //     ancestor: overlayBox,
    //   );
    //   final Offset bottomRight = buttonBox.localToGlobal(
    //     buttonBox.size.bottomRight(Offset.zero),
    //     ancestor: overlayBox,
    //   );
    //   final position = RelativeRect.fromLTRB(
    //     topLeft.dx,
    //     topLeft.dy,
    //     overlayBox.size.width - bottomRight.dx,
    //     overlayBox.size.height - bottomRight.dy,
    //   );

    //   selected = await showMenu<PolygonFeature>(
    //     context: context,
    //     position: position,
    //     items: polygons
    //         .map(
    //           (polygon) => PopupMenuItem<PolygonFeature>(
    //             value: polygon,
    //             child: Text(_polygonDisplayName(polygon)),
    //           ),
    //         )
    //         .toList(),
    //   );

    //   if (selected == null) {
    //     return;
    //   }
    // } else {
    //   selected = await showModalBottomSheet<PolygonFeature>(
    //     context: context,
    //     showDragHandle: true,
    //     builder: (context) {
    //       return SafeArea(
    //         child: ListView(
    //           shrinkWrap: true,
    //           children: [
    //             const ListTile(
    //               title: Text('একটি পলিগন নির্বাচন করুন'),
    //             ),
    //             const Divider(height: 0),
    //             ...polygons.map(
    //               (polygon) => ListTile(
    //                 title: Text(_polygonDisplayName(polygon)),
    //                 onTap: () => Navigator.of(context).pop(polygon),
    //               ),
    //             ),
    //           ],
    //         ),
    //       );
    //     },
    //   );

    //   if (selected == null) {
    //     return;
    //   }
    // }
    //print(selected.id);
    // controller.focusPolygon(polygons[59]);
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

  Future<void> _showCustomPlaceDetails(CustomPlace place) async {
    setState(() {
      _selectedCustomPlace = place;
    });

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => PlaceDetailsSheet(place: place),
    );

    if (!mounted) return;
    setState(() {
      _selectedCustomPlace = null;
    });
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
