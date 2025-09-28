import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'package:balumohol/core/utils/formatting.dart';
import 'package:balumohol/core/utils/string_extensions.dart';
import 'package:balumohol/features/geofence/constants.dart';
import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/presentation/widgets/google_style_marker.dart';

class AddPlacePage extends StatefulWidget {
  const AddPlacePage({
    super.key,
    required this.initialLocation,
  });

  final LatLng initialLocation;

  @override
  State<AddPlacePage> createState() => _AddPlacePageState();
}

class _AddPlacePageState extends State<AddPlacePage> {
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
                  final matches = placeCategories
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
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(source: source);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageFileName = picked.name;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: ${e.message ?? e.code}')),
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
      return 'এই ঘরটি পূরণ করুন';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final location = _selectedLocation;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location on the map.')),
      );
      return;
    }

    final place = CustomPlace(
      name: _nameController.text.trim(),
      category: _categoryController.text.trim(),
      address: _addressController.text.trim(),
      location: location,
      locatedWithin: _locatedWithinController.text.emptyToNull(),
      phone: _phoneController.text.emptyToNull(),
      website: _websiteController.text.emptyToNull(),
      description: _descriptionController.text.emptyToNull(),
      createdAt: DateTime.now(),
      imageBase64:
          _selectedImageBytes != null ? base64Encode(_selectedImageBytes!) : null,
    );

    if (!mounted) return;
    Navigator.of(context).pop(place);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedLocation = _selectedLocation;
    final locationSummary = selectedLocation != null
        ? formatLatLng(selectedLocation, fractionDigits: 6)
        : 'Tap on the map to select a location';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add place'),
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose location',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            height: 220,
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: widget.initialLocation,
                                initialZoom: 17,
                                onTap: (tapPosition, point) {
                                  _selectLocation(point);
                                },
                                onMapEvent: (event) {
                                  _mapCenter = _mapController.camera.center;
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.example.balumohol',
                                ),
                                if (selectedLocation != null)
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: selectedLocation,
                                        width: 40,
                                        height: 40,
                                        child: const GoogleStyleMarker(),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
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
                        ],
                        const SizedBox(height: 12),
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
              );
            },
          ),
        ),
      ),
    );
  }
}
