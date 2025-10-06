import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:balumohol/core/language/language_controller.dart';
import 'package:balumohol/core/language/localized_text.dart';
import 'package:balumohol/features/geofence/models/polygon_field_template.dart';
import 'package:balumohol/features/geofence/models/user_polygon.dart';
import 'package:balumohol/features/geofence/providers/geofence_map_controller.dart';

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

const List<PolygonColorOption> kPolygonColorOptions = <PolygonColorOption>[
  PolygonColorOption(
    label: LocalizedText(bangla: 'নীল', english: 'Blue'),
    color: Color(0xFF1976D2),
  ),
  PolygonColorOption(
    label: LocalizedText(bangla: 'সবুজ', english: 'Green'),
    color: Color(0xFF2E7D32),
  ),
  PolygonColorOption(
    label: LocalizedText(bangla: 'কমলা', english: 'Orange'),
    color: Color(0xFFEF6C00),
  ),
  PolygonColorOption(
    label: LocalizedText(bangla: 'বেগুনি', english: 'Purple'),
    color: Color(0xFF6A1B9A),
  ),
  PolygonColorOption(
    label: LocalizedText(bangla: 'লাল', english: 'Red'),
    color: Color(0xFFC62828),
  ),
];

class _DrawPolygonPageState extends State<DrawPolygonPage> {
  final MapController _mapController = MapController();
  final List<LatLng> _points = <LatLng>[];

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

    final language = context.read<LanguageController>().language;
    final details = await _promptForPolygonDetails(language);
    if (!mounted || details == null) {
      return;
    }

    final trimmedName = details.name.trim();
    final displayName = trimmedName.isEmpty
        ? _localizedText(language, 'কাস্টম পলিগন', 'Custom polygon')
        : trimmedName;

    final templateDefinitions =
        _templateDefinitionsFromFields(details.fields);

    final polygon = UserPolygon(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: displayName,
      colorValue: details.color.value,
      points: List<LatLng>.from(_points),
      fields: details.fields,
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      PolygonCreationResult(
        polygon: polygon,
        templateDefinitions: templateDefinitions,
      ),
    );
  }

  Future<PolygonDetailsResult?> _promptForPolygonDetails(
      AppLanguage language) async {
    final templates =
        context.read<GeofenceMapController>().polygonTemplates.toList();
    return showDialog<PolygonDetailsResult>(
      context: context,
          builder: (context) {
            return PolygonDetailsFormDialog(
              language: language,
              colorOptions: kPolygonColorOptions,
              templates: templates,
            );
          },
        );
  }

  List<PolygonFieldDefinition> _templateDefinitionsFromFields(
    List<UserPolygonField> fields,
  ) {
    return fields
        .map(
          (field) => PolygonFieldDefinition(
            name: field.name.trim(),
            type: field.type,
          ),
        )
        .where((definition) => definition.name.isNotEmpty)
        .toList(growable: false);
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
    final language = context.watch<LanguageController>().language;
    final pointCount = _points.length;
    final instructionText = pointCount >= 3
        ? _localizedText(
            language,
            'সংরক্ষণ করতে "সংরক্ষণ করুন" চাপুন।',
            'Tap "Save" to store the polygon.',
          )
        : _localizedText(
            language,
            'কমপক্ষে ৩টি পয়েন্ট প্রয়োজন।',
            'At least 3 points are required.',
          );

    final pointMarkers = _buildPointMarkers();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _localizedText(language, 'নতুন পলিগন আঁকুন', 'Draw new polygon'),
        ),
      ),
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
                    child: _InstructionBanner(language: language),
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
                      _localizedText(
                        language,
                        'যোগ করা পয়েন্ট: $pointCount',
                        'Points added: $pointCount',
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _localizedText(
                        language,
                        'মানচিত্রে ট্যাপ করে পয়েন্ট যোগ করুন। $instructionText',
                        'Tap the map to add points. $instructionText',
                      ),
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
                          label: Text(
                            _localizedText(language, 'আনডু', 'Undo'),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: pointCount > 0
                              ? () => setState(() {
                                    _points.clear();
                                  })
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            _localizedText(language, 'সব মুছুন', 'Clear all'),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _cancelDrawing,
                          icon: const Icon(Icons.close),
                          label: Text(
                            _localizedText(language, 'বাতিল', 'Cancel'),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed:
                              pointCount >= 3 ? _savePolygon : null,
                          icon: const Icon(Icons.check),
                          label: Text(
                            _localizedText(language, 'সংরক্ষণ করুন', 'Save'),
                          ),
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
  const _InstructionBanner({super.key, required this.language});

  final AppLanguage language;

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
                _localizedText(
                  language,
                  'মানচিত্রে ট্যাপ করে পয়েন্ট যোগ করুন',
                  'Tap the map to add points',
                ),
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

class PolygonDetailsFormDialog extends StatefulWidget {
  const PolygonDetailsFormDialog({
    required this.language,
    required this.colorOptions,
    this.templates = const <PolygonFieldTemplate>[],
    this.initialName,
    this.initialColor,
    this.initialFields = const <UserPolygonField>[],
    this.allowTemplateSelection = true,
  });

  final AppLanguage language;
  final List<PolygonColorOption> colorOptions;
  final List<PolygonFieldTemplate> templates;
  final String? initialName;
  final Color? initialColor;
  final List<UserPolygonField> initialFields;
  final bool allowTemplateSelection;

  @override
  State<PolygonDetailsFormDialog> createState() =>
      _PolygonDetailsFormDialogState();
}

class _PolygonDetailsFormDialogState extends State<PolygonDetailsFormDialog> {
  late final TextEditingController _nameController;
  late Color _selectedColor;
  final List<_EditablePolygonField> _editableFields = <_EditablePolygonField>[];
  PolygonFieldTemplate? _appliedTemplate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedColor = widget.initialColor ?? widget.colorOptions.first.color;
    for (final field in widget.initialFields) {
      _editableFields.add(_EditablePolygonField.fromUserField(field));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final field in _editableFields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _addField() async {
    final field = await _showFieldCreationDialog(widget.language);
    if (field == null || !mounted) {
      return;
    }
    setState(() {
      _editableFields.add(field);
      _appliedTemplate = null;
    });
  }

  void _removeField(int index) {
    final removed = _editableFields[index];
    setState(() {
      _editableFields.removeAt(index);
      _appliedTemplate = null;
    });
    removed.dispose();
  }

  Future<void> _selectTemplate() async {
    if (!widget.allowTemplateSelection || widget.templates.isEmpty) {
      return;
    }

    final selected = await showModalBottomSheet<PolygonFieldTemplate>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final language = widget.language;
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            itemCount: widget.templates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final template = widget.templates[index];
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                leading: const Icon(Icons.content_paste_go),
                title: Text(template.name),
                subtitle: Text(
                  _localizedText(
                    language,
                    '${template.fields.length} টি ক্ষেত্র',
                    '${template.fields.length} fields',
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop(template),
              );
            },
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    _applyTemplate(selected);
  }

  void _applyTemplate(PolygonFieldTemplate template) {
    final nextFields = template.fields
        .map(_EditablePolygonField.fromDefinition)
        .toList(growable: true);
    for (final field in _editableFields) {
      field.dispose();
    }
    setState(() {
      _editableFields
        ..clear()
        ..addAll(nextFields);
      _appliedTemplate = template;
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        _localizedText(language, 'পলিগনের বিস্তারিত', 'Polygon details'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: _localizedText(language, 'নাম', 'Name'),
                hintText: _localizedText(
                  language,
                  'পলিগনের নাম লিখুন',
                  'Enter polygon name',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _localizedText(language, 'রং নির্বাচন করুন', 'Choose a color'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final option in widget.colorOptions)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() {
                        _selectedColor = option.color;
                      }),
                      borderRadius: BorderRadius.circular(28),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _PolygonColorPreview(
                          color: option.color,
                          label: option.label.resolve(language),
                          selected: _selectedColor == option.color,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _localizedText(
                      language,
                      'অতিরিক্ত তথ্য',
                      'Additional information',
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: _localizedText(language, 'ক্ষেত্র যোগ করুন', 'Add field'),
                  onPressed: _addField,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.allowTemplateSelection && widget.templates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _selectTemplate,
                      icon: const Icon(Icons.content_paste_go),
                      label: Text(
                        _localizedText(
                          language,
                          'সংরক্ষিত টেমপ্লেট ব্যবহার করুন',
                          'Use saved template',
                        ),
                      ),
                    ),
                    if (_appliedTemplate != null)
                      InputChip(
                        avatar: const Icon(Icons.check, size: 18),
                        label: Text(_appliedTemplate!.name),
                        onDeleted: () {
                          setState(() {
                            _appliedTemplate = null;
                          });
                        },
                      ),
                  ],
                ),
              ),
            if (_editableFields.isEmpty)
              Text(
                _localizedText(
                  language,
                  'আপনি অতিরিক্ত কোনো তথ্য যোগ করেননি।',
                  'You have not added any extra information.',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._editableFields.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PolygonFieldEditor(
                    field: entry.value,
                    language: language,
                    onRemove: () => _removeField(entry.key),
                    onDateChanged: (date) {
                      setState(() {
                        entry.value.dateValue = date;
                      });
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _localizedText(language, 'বাতিল', 'Cancel'),
          ),
        ),
        FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
              PolygonDetailsResult(
                name: _nameController.text,
                color: _selectedColor,
                fields: _editableFields
                    .map((field) => field.toUserPolygonField())
                    .whereType<UserPolygonField>()
                    .toList(),
              ),
            );
          },
          child: Text(
            _localizedText(language, 'সংরক্ষণ করুন', 'Save'),
          ),
        ),
      ],
    );
  }

  Future<_EditablePolygonField?> _showFieldCreationDialog(
      AppLanguage language) {
    return showDialog<_EditablePolygonField>(
      context: context,
      builder: (context) => _AddPolygonFieldDialog(language: language),
    );
  }
}

class _AddPolygonFieldDialog extends StatefulWidget {
  const _AddPolygonFieldDialog({required this.language});

  final AppLanguage language;

  @override
  State<_AddPolygonFieldDialog> createState() => _AddPolygonFieldDialogState();
}

class _AddPolygonFieldDialogState extends State<_AddPolygonFieldDialog> {
  late final TextEditingController _nameController;
  UserPolygonFieldType _selectedType = UserPolygonFieldType.text;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _nameError = _localizedText(
          widget.language,
          'ক্ষেত্রের নাম লিখুন',
          'Enter a field name',
        );
      });
      return;
    }
    Navigator.of(context).pop(
      _EditablePolygonField(
        name: name,
        type: _selectedType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    return AlertDialog(
      title: Text(
        _localizedText(language, 'ক্ষেত্র যোগ করুন', 'Add field'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: _localizedText(
                  language,
                  'ক্ষেত্রের নাম',
                  'Field name',
                ),
                hintText: _localizedText(
                  language,
                  'যেমন: মালিকের নাম',
                  'e.g. Owner name',
                ),
                errorText: _nameError,
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() {
                    _nameError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<UserPolygonFieldType>(
              value: _selectedType,
              decoration: InputDecoration(
                labelText: _localizedText(
                  language,
                  'ডেটার ধরন',
                  'Data type',
                ),
              ),
              items: UserPolygonFieldType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(
                        _fieldTypeLabel(type, language),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedType = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _localizedText(language, 'বাতিল', 'Cancel'),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            _localizedText(language, 'যোগ করুন', 'Add'),
          ),
        ),
      ],
    );
  }
}

class PolygonCreationResult {
  const PolygonCreationResult({
    required this.polygon,
    required this.templateDefinitions,
  });

  final UserPolygon polygon;
  final List<PolygonFieldDefinition> templateDefinitions;
}

class PolygonDetailsResult {
  const PolygonDetailsResult({
    required this.name,
    required this.color,
    required this.fields,
  });

  final String name;
  final Color color;
  final List<UserPolygonField> fields;
}

class _EditablePolygonField {
  _EditablePolygonField({
    required this.name,
    required this.type,
    dynamic initialValue,
  }) : controller = TextEditingController() {
    _applyInitialValue(initialValue);
  }

  factory _EditablePolygonField.fromDefinition(
    PolygonFieldDefinition definition,
  ) {
    return _EditablePolygonField(
      name: definition.name,
      type: definition.type,
    );
  }

  factory _EditablePolygonField.fromUserField(UserPolygonField field) {
    return _EditablePolygonField(
      name: field.name,
      type: field.type,
      initialValue: field.value,
    );
  }

  void _applyInitialValue(dynamic initialValue) {
    switch (type) {
      case UserPolygonFieldType.text:
        if (initialValue is String) {
          controller.text = initialValue.trim();
        } else if (initialValue != null) {
          controller.text = initialValue.toString();
        }
        break;
      case UserPolygonFieldType.number:
        if (initialValue is num) {
          controller.text = initialValue.toString();
        } else if (initialValue is String) {
          controller.text = initialValue.trim();
        }
        break;
      case UserPolygonFieldType.date:
        if (initialValue is DateTime) {
          dateValue = initialValue;
        } else if (initialValue is String) {
          dateValue = DateTime.tryParse(initialValue);
        }
        break;
    }
  }

  UserPolygonField? toUserPolygonField() {
    switch (type) {
      case UserPolygonFieldType.text:
        final text = controller.text.trim();
        if (text.isEmpty) return null;
        return UserPolygonField(name: name, type: type, value: text);
      case UserPolygonFieldType.number:
        final text = controller.text.trim();
        if (text.isEmpty) return null;
        final parsed = num.tryParse(text);
        return UserPolygonField(
          name: name,
          type: type,
          value: parsed ?? text,
        );
      case UserPolygonFieldType.date:
        final date = dateValue;
        if (date == null) return null;
        return UserPolygonField(name: name, type: type, value: date);
    }
  }

  String? get formattedDate {
    final date = dateValue;
    if (date == null) return null;
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  void dispose() {
    controller.dispose();
  }

  final String name;
  final UserPolygonFieldType type;
  final TextEditingController controller;
  DateTime? dateValue;
}

class _PolygonFieldEditor extends StatelessWidget {
  const _PolygonFieldEditor({
    required this.field,
    required this.language,
    required this.onRemove,
    required this.onDateChanged,
  });

  final _EditablePolygonField field;
  final AppLanguage language;
  final VoidCallback onRemove;
  final ValueChanged<DateTime?> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeLabel = _fieldTypeLabel(field.type, language);
    final Widget input;
    switch (field.type) {
      case UserPolygonFieldType.text:
        input = TextField(
          controller: field.controller,
          decoration: InputDecoration(
            labelText: _localizedText(language, 'মান', 'Value'),
            hintText: _fieldValueHint(field.type, language),
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
        );
        break;
      case UserPolygonFieldType.number:
        input = TextField(
          controller: field.controller,
          decoration: InputDecoration(
            labelText: _localizedText(language, 'মান', 'Value'),
            hintText: _fieldValueHint(field.type, language),
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(
            signed: false,
            decimal: true,
          ),
          textInputAction: TextInputAction.done,
        );
        break;
      case UserPolygonFieldType.date:
        final localizations = MaterialLocalizations.of(context);
        final label = field.dateValue != null
            ? localizations.formatMediumDate(field.dateValue!)
            : _fieldValueHint(field.type, language);
        input = Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final initial = field.dateValue ?? now;
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(1970),
                    lastDate: DateTime(now.year + 30),
                  );
                  if (selected != null) {
                    onDateChanged(
                      DateTime(selected.year, selected.month, selected.day),
                    );
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(label),
              ),
            ),
            if (field.dateValue != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: _localizedText(
                  language,
                  'তারিখ মুছুন',
                  'Clear date',
                ),
                onPressed: () => onDateChanged(null),
                icon: const Icon(Icons.clear),
              ),
            ],
          ],
        );
        break;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    field.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    typeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _localizedText(language, 'মুছে ফেলুন', 'Remove'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            input,
          ],
        ),
      ),
    );
  }
}

String _fieldTypeLabel(UserPolygonFieldType type, AppLanguage language) {
  switch (type) {
    case UserPolygonFieldType.text:
      return _localizedText(language, 'টেক্সট', 'Text');
    case UserPolygonFieldType.number:
      return _localizedText(language, 'সংখ্যা', 'Number');
    case UserPolygonFieldType.date:
      return _localizedText(language, 'তারিখ', 'Date');
  }
}

String _fieldValueHint(UserPolygonFieldType type, AppLanguage language) {
  switch (type) {
    case UserPolygonFieldType.text:
      return _localizedText(language, 'তথ্য লিখুন', 'Enter information');
    case UserPolygonFieldType.number:
      return _localizedText(language, 'সংখ্যা লিখুন', 'Enter a number');
    case UserPolygonFieldType.date:
      return _localizedText(language, 'তারিখ নির্বাচন করুন', 'Select a date');
  }
}

class PolygonColorOption {
  const PolygonColorOption({required this.label, required this.color});

  final LocalizedText label;
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

String _localizedText(
  AppLanguage language,
  String bangla,
  String english,
) {
  return language.isBangla ? bangla : english;
}
