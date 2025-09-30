import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:balumohol/features/geofence/models/user_polygon.dart';

class DrawPolygonPage extends StatefulWidget {
  const DrawPolygonPage({
    super.key,
    required this.initialCenter,
    required this.tileUrlTemplate,
    this.tileSubdomains,
  });

  final LatLng initialCenter;
  final String tileUrlTemplate;
  final List<String>? tileSubdomains;

  @override
  State<DrawPolygonPage> createState() => _DrawPolygonPageState();
}

class _DrawPolygonPageState extends State<DrawPolygonPage> {
  final MapController _mapController = MapController();
  final List<LatLng> _points = <LatLng>[];

  static const List<_PolygonColorOption> _polygonColorOptions =
      <_PolygonColorOption>[
    _PolygonColorOption('নীল', Color(0xFF1976D2)),
    _PolygonColorOption('সবুজ', Color(0xFF2E7D32)),
    _PolygonColorOption('কমলা', Color(0xFFEF6C00)),
    _PolygonColorOption('বেগুনি', Color(0xFF6A1B9A)),
    _PolygonColorOption('লাল', Color(0xFFC62828)),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(widget.initialCenter, 16);
    });
  }

  void _addPoint(LatLng point) {
    setState(() {
      _points.add(point);
    });
  }

  void _undoPoint() {
    if (_points.isEmpty) {
      return;
    }
    setState(() {
      _points.removeLast();
    });
  }

  void _cancelDrawing() {
    Navigator.of(context).pop();
  }

  Future<void> _savePolygon() async {
    if (_points.length < 3) {
      return;
    }

    final details = await _promptForPolygonDetails();
    if (!mounted || details == null) {
      return;
    }

    final trimmedName = details.name.trim();
    final displayName =
        trimmedName.isEmpty ? 'কাস্টম পলিগন' : trimmedName;

    final polygon = UserPolygon(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: displayName,
      colorValue: details.color.value,
      points: List<LatLng>.from(_points),
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(polygon);
  }

  Future<_PolygonDetails?> _promptForPolygonDetails() async {
    final nameController = TextEditingController();
    Color selectedColor = _polygonColorOptions.first.color;
    try {
      return await showDialog<_PolygonDetails>(
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
                        _PolygonDetails(
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

  List<Marker> _buildPointMarkers() {
    return List<Marker>.generate(
      _points.length,
      (index) {
        final point = _points[index];
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pointCount = _points.length;
    final instructionText = pointCount >= 3
        ? 'সংরক্ষণ করতে "সংরক্ষণ করুন" চাপুন।'
        : 'কমপক্ষে ৩টি পয়েন্ট প্রয়োজন।';

    final pointMarkers = _buildPointMarkers();

    return Scaffold(
      appBar: AppBar(title: const Text('নতুন পলিগন আঁকুন')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.initialCenter,
                    initialZoom: 16,
                    onTap: (tapPosition, point) => _addPoint(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: widget.tileUrlTemplate,
                      subdomains: widget.tileSubdomains ?? const <String>[],
                      userAgentPackageName: 'com.example.balumohol',
                    ),
                    if (pointCount >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _points,
                            color: Colors.deepOrangeAccent.withOpacity(0.2),
                            borderColor: Colors.deepOrangeAccent,
                            borderStrokeWidth: 3,
                            isFilled: true,
                          ),
                        ],
                      ),
                    if (pointCount >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [
                              ..._points,
                              if (pointCount >= 3) _points.first,
                            ],
                            strokeWidth: 3,
                            color: Colors.deepOrangeAccent,
                          ),
                        ],
                      ),
                    if (pointMarkers.isNotEmpty)
                      MarkerLayer(markers: pointMarkers),
                  ],
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: const _InstructionBanner(),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(18),
              color: theme.colorScheme.surface,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'যোগ করা পয়েন্ট: $pointCount',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'মানচিত্রে ট্যাপ করে পয়েন্ট যোগ করুন। $instructionText',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: pointCount > 0 ? _undoPoint : null,
                          icon: const Icon(Icons.undo),
                          label: const Text('আনডু'),
                        ),
                        OutlinedButton.icon(
                          onPressed: pointCount > 0
                              ? () => setState(() {
                                    _points.clear();
                                  })
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('সব মুছুন'),
                        ),
                        TextButton.icon(
                          onPressed: _cancelDrawing,
                          icon: const Icon(Icons.close),
                          label: const Text('বাতিল'),
                        ),
                        FilledButton.icon(
                          onPressed:
                              pointCount >= 3 ? _savePolygon : null,
                          icon: const Icon(Icons.check),
                          label: const Text('সংরক্ষণ করুন'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionBanner extends StatelessWidget {
  const _InstructionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      color: theme.colorScheme.surface.withOpacity(0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'মানচিত্রে ট্যাপ করে পয়েন্ট যোগ করুন',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolygonDetails {
  const _PolygonDetails({required this.name, required this.color});

  final String name;
  final Color color;
}

class _PolygonColorOption {
  const _PolygonColorOption(this.label, this.color);

  final String label;
  final Color color;
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
