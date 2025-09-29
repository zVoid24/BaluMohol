import 'dart:math' as math;

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

class _GeofenceMapPageState extends State<GeofenceMapPage>
    with TickerProviderStateMixin {
  static const double _customPlaceMarkerZoomThreshold = 14;
  static const double _customPlaceMarkerBaseWidth = 160;
  static const double _customPlaceMarkerBaseHeight = 64;

  bool _initialised = false;
  double _currentZoom = 15;
  double _currentRotation = 0;
  bool _statusCollapsed = false;
  CustomPlace? _selectedCustomPlace;
  final GlobalKey _polygonButtonKey = GlobalKey();

  late final AnimationController _rotationController;
  late final AnimationController _cameraController;
  Animation<double>? _rotationAnimation;
  Animation<double>? _cameraAnimation;
  VoidCallback? _rotationAnimationListener;
  VoidCallback? _cameraAnimationListener;
  AnimationStatusListener? _rotationStatusListener;
  AnimationStatusListener? _cameraStatusListener;
  Tween<double>? _latitudeTween;
  Tween<double>? _longitudeTween;
  Tween<double>? _zoomTween;

  bool get _showCustomPlaceMarkers =>
      _currentZoom >= _customPlaceMarkerZoomThreshold;

  @override
  void initState() {
    super.initState();
    _currentZoom = 15;
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _cameraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
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
  void dispose() {
    _removeRotationAnimationCallbacks();
    _removeCameraAnimationCallbacks();
    _rotationController.dispose();
    _cameraController.dispose();
    super.dispose();
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
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildQuickActionPanel(context, controller),
            const SizedBox(height: 12),
            _buildPrimaryActionPanel(context, controller),
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
                final rotation = event.camera.rotation;
                final normalizedRotation = _normalizeRotation(rotation);
                var shouldUpdate = false;

                if ((zoom - _currentZoom).abs() > 0.01) {
                  _currentZoom = zoom;
                  shouldUpdate = true;
                }
                if ((normalizedRotation - _currentRotation).abs() > 0.001) {
                  _currentRotation = normalizedRotation;
                  shouldUpdate = true;
                }

                if (event.source == MapEventSource.onDrag ||
                    event.source == MapEventSource.onMultiFingerGesture ||
                    event.source == MapEventSource.onScrollWheel ||
                    event.source == MapEventSource.onDoubleTapZoom) {
                  if (_cameraController.isAnimating) {
                    _cameraController.stop();
                    _removeCameraAnimationCallbacks();
                  }
                  if (_rotationController.isAnimating) {
                    _rotationController.stop();
                    _removeRotationAnimationCallbacks();
                  }
                }

                if (shouldUpdate && mounted) {
                  setState(() {});
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
                child: _buildStatusPanel(
                  context: context,
                  accuracyText: accuracyText,
                  controller: controller,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel({
    required BuildContext context,
    required String accuracyText,
    required GeofenceMapController controller,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.94),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _toggleStatusPanel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.gps_fixed, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'অবস্থান তথ্য',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                controller.statusMessage,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildAccuracyChip(context, accuracyText),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _statusCollapsed ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.keyboard_arrow_up,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: StatusCard(
                    accuracyText: accuracyText,
                    statusMessage: controller.statusMessage,
                    errorMessage: controller.errorMessage,
                  ),
                ),
                crossFadeState: _statusCollapsed
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 250),
                sizeCurve: Curves.easeInOutCubic,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccuracyChip(BuildContext context, String accuracyText) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'সঠিকতা: $accuracyText',
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildQuickActionPanel(
    BuildContext context,
    GeofenceMapController controller,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCircularActionButton(
              context: context,
              tooltip: 'উত্তরমুখে ঘোরান',
              icon: Transform.rotate(
                angle: -_rotationToRadians(_currentRotation),
                child: const Icon(Icons.explore),
              ),
              onPressed: () => _rotateToNorth(controller),
            ),
            const SizedBox(height: 12),
            _buildCircularActionButton(
              context: context,
              tooltip: 'বর্তমান অবস্থানে যান',
              icon: const Icon(Icons.my_location),
              onPressed: () => _goToCurrentLocation(controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryActionPanel(
    BuildContext context,
    GeofenceMapController controller,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelButton(
              buttonKey: _polygonButtonKey,
              label: 'পলিগন নির্বাচন',
              icon: Icons.layers,
              onPressed: () => _showPolygonSelector(controller),
            ),
            const SizedBox(height: 10),
            _PanelButton(
              label: 'এখন ক্যালিব্রেট করুন',
              icon: Icons.compass_calibration,
              onPressed:
                  controller.permissionDenied ? null : () => controller.calibrateNow(),
              variant: _PanelButtonVariant.tonal,
            ),
            const SizedBox(height: 10),
            _PanelButton(
              label: 'Add place',
              icon: Icons.add_location_alt,
              onPressed: () => _startAddPlaceFlow(controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularActionButton({
    required BuildContext context,
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.primaryContainer,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        icon: icon,
        onPressed: onPressed,
        color: colorScheme.onPrimaryContainer,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }

  void _toggleStatusPanel() {
    setState(() {
      _statusCollapsed = !_statusCollapsed;
    });
  }

  void _rotateToNorth(GeofenceMapController controller) {
    final rotation = controller.mapController.camera.rotation;
    final fullRotation = rotation.abs() > 2 * math.pi ? 360.0 : 2 * math.pi;
    final targetRotation = (rotation / fullRotation).roundToDouble() * fullRotation;

    if ((rotation - targetRotation).abs() < 0.001) {
      controller.resetRotation();
      return;
    }

    _rotationController.stop();
    _removeRotationAnimationCallbacks();

    final distance = (targetRotation - rotation).abs();
    final durationMs = (320 + (distance / fullRotation) * 280).clamp(320, 650).round();
    _rotationController.duration = Duration(milliseconds: durationMs);

    _rotationAnimation = Tween<double>(
      begin: rotation,
      end: targetRotation,
    ).animate(
      CurvedAnimation(
        parent: _rotationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _rotationAnimationListener = () {
      if (_rotationAnimation != null) {
        controller.mapController.rotate(_rotationAnimation!.value);
      }
    };

    _rotationStatusListener = (status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.resetRotation();
        _removeRotationAnimationCallbacks();
      }
    };

    _rotationController
      ..addListener(_rotationAnimationListener!)
      ..addStatusListener(_rotationStatusListener!);
    _rotationController.forward(from: 0);
  }

  void _animateCameraTo({
    required GeofenceMapController controller,
    required LatLng target,
    double? zoom,
    Duration? duration,
  }) {
    final camera = controller.mapController.camera;
    final origin = camera.center;
    final beginZoom = camera.zoom;

    if ((origin.latitude - target.latitude).abs() < 1e-7 &&
        (origin.longitude - target.longitude).abs() < 1e-7 &&
        (zoom == null || (zoom - beginZoom).abs() < 0.01)) {
      controller.moveMap(target, zoom ?? beginZoom);
      return;
    }

    final distanceMeters = Distance().as(LengthUnit.Meter, origin, target);
    final travelFactor = (distanceMeters / 2500).clamp(0.0, 1.0);
    final computedDuration = duration ??
        Duration(milliseconds: (420 + travelFactor * 320).round());

    _cameraController.stop();
    _removeCameraAnimationCallbacks();
    _cameraController.duration = computedDuration;

    _latitudeTween = Tween<double>(
      begin: origin.latitude,
      end: target.latitude,
    );
    _longitudeTween = Tween<double>(
      begin: origin.longitude,
      end: target.longitude,
    );
    _zoomTween = zoom != null ? Tween<double>(begin: beginZoom, end: zoom) : null;

    _cameraAnimation = CurvedAnimation(
      parent: _cameraController,
      curve: Curves.easeInOutCubic,
    );

    _cameraAnimationListener = () {
      if (_cameraAnimation == null) return;
      final progress = _cameraAnimation!.value;
      final latitude = _latitudeTween!.transform(progress);
      final longitude = _longitudeTween!.transform(progress);
      final zoomValue = _zoomTween?.transform(progress) ?? beginZoom;
      controller.mapController.move(LatLng(latitude, longitude), zoomValue);
    };

    _cameraStatusListener = (status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.moveMap(target, zoom ?? beginZoom);
        _removeCameraAnimationCallbacks();
      }
    };

    _cameraController
      ..addListener(_cameraAnimationListener!)
      ..addStatusListener(_cameraStatusListener!);
    _cameraController.forward(from: 0);
  }

  void _removeRotationAnimationCallbacks() {
    if (_rotationAnimationListener != null) {
      _rotationController.removeListener(_rotationAnimationListener!);
      _rotationAnimationListener = null;
    }
    if (_rotationStatusListener != null) {
      _rotationController.removeStatusListener(_rotationStatusListener!);
      _rotationStatusListener = null;
    }
    _rotationAnimation = null;
  }

  void _removeCameraAnimationCallbacks() {
    if (_cameraAnimationListener != null) {
      _cameraController.removeListener(_cameraAnimationListener!);
      _cameraAnimationListener = null;
    }
    if (_cameraStatusListener != null) {
      _cameraController.removeStatusListener(_cameraStatusListener!);
      _cameraStatusListener = null;
    }
    _cameraAnimation = null;
    _latitudeTween = null;
    _longitudeTween = null;
    _zoomTween = null;
  }

  double _normalizeRotation(double rotation) {
    final fullRotation = rotation.abs() > 2 * math.pi ? 360.0 : 2 * math.pi;
    var normalized = rotation.remainder(fullRotation);
    final half = fullRotation / 2;
    if (normalized > half) normalized -= fullRotation;
    if (normalized < -half) normalized += fullRotation;
    return normalized;
  }

  double _rotationToRadians(double rotation) {
    if (rotation.abs() > 2 * math.pi) {
      return rotation * math.pi / 180;
    }
    return rotation;
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
      _animateCameraTo(
        controller: controller,
        target: location,
        zoom: defaultFollowZoom,
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('বর্তমান অবস্থান এখনও পাওয়া যায়নি।')),
    );
  }

  Future<void> _showPolygonSelector(GeofenceMapController controller) async {
    final polygons = controller.polygons;
    if (polygons.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('কোনও পলিগন পাওয়া যায়নি।')),
      );
      return;
    }

    if (polygons.length == 1) {
      controller.focusPolygon(polygons.first);
      return;
    }

    final RenderBox? buttonBox =
        _polygonButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final OverlayState? overlayState = Overlay.of(context);
    final RenderBox? overlayBox =
        overlayState?.context.findRenderObject() as RenderBox?;

    PolygonFeature? selected;
    if (buttonBox != null && overlayBox != null) {
      final Offset topLeft = buttonBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      final Offset bottomRight = buttonBox.localToGlobal(
        buttonBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      );
      final position = RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlayBox.size.width - bottomRight.dx,
        overlayBox.size.height - bottomRight.dy,
      );

      selected = await showMenu<PolygonFeature>(
        context: context,
        position: position,
        items: polygons
            .map(
              (polygon) => PopupMenuItem<PolygonFeature>(
                value: polygon,
                child: Text(_polygonDisplayName(polygon)),
              ),
            )
            .toList(),
      );

      if (selected == null) {
        return;
      }
    } else {
      selected = await showModalBottomSheet<PolygonFeature>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text('একটি পলিগন নির্বাচন করুন'),
                ),
                const Divider(height: 0),
                ...polygons.map(
                  (polygon) => ListTile(
                    title: Text(_polygonDisplayName(polygon)),
                    onTap: () => Navigator.of(context).pop(polygon),
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (selected == null) {
        return;
      }
    }

    controller.focusPolygon(selected);
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

enum _PanelButtonVariant { filled, tonal }

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    this.buttonKey,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = _PanelButtonVariant.filled,
  });

  final Key? buttonKey;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final _PanelButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    final Widget button = variant == _PanelButtonVariant.tonal
        ? FilledButton.tonalIcon(
            key: buttonKey,
            onPressed: onPressed,
            style: buttonStyle,
            icon: Icon(icon),
            label: Text(label),
          )
        : FilledButton.icon(
            key: buttonKey,
            onPressed: onPressed,
            style: buttonStyle,
            icon: Icon(icon),
            label: Text(label),
          );

    return SizedBox(
      width: 240,
      child: button,
    );
  }
}
