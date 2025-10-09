import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
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
    this.existingPlace,
  });

  final LatLng initialLocation;
  final CustomPlace? existingPlace;

  @override
  State<AddPlacePage> createState() => _AddPlacePageState();
}

class _AddressSuggestion {
  const _AddressSuggestion({required this.displayName, required this.location});

  final String displayName;
  final LatLng location;

  factory _AddressSuggestion.fromJson(Map<String, dynamic> json) {
    double _parseCoordinate(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.parse(value as String);
    }

    return _AddressSuggestion(
      displayName: json['display_name'] as String? ?? '',
      location: LatLng(
        _parseCoordinate(json['lat']),
        _parseCoordinate(json['lon']),
      ),
    );
  }
}

class _AddPlacePageState extends State<AddPlacePage> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();
  final ImagePicker _imagePicker = ImagePicker();
  final FocusNode _categoryFocusNode = FocusNode();
  final FocusNode _addressFocusNode = FocusNode();

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
  bool _imageRemoved = false;
  Timer? _addressDebounce;
  int _addressRequestId = 0;
  int _reverseGeocodeRequestId = 0;
  bool _isFetchingAddressOptions = false;
  bool _isReverseGeocoding = false;
  bool _isHandlingAddressSelection = false;
  List<_AddressSuggestion> _addressOptions = <_AddressSuggestion>[];
  String? _addressLookupMessage;
  bool _addressLookupIsError = false;
  String? _quickCategorySelection;

  @override
  void initState() {
    super.initState();
    final existingPlace = widget.existingPlace;
    _nameController = TextEditingController(text: existingPlace?.name ?? '');
    _categoryController = TextEditingController(
      text: existingPlace?.category ?? '',
    );
    _quickCategorySelection = _deriveQuickSelection(
      _categoryController.text,
      previous: null,
    );
    _categoryController.addListener(_handleCategoryChanged);
    _addressController = TextEditingController(
      text: existingPlace?.address ?? '',
    );
    _locatedWithinController = TextEditingController(
      text: existingPlace?.locatedWithin ?? '',
    );
    _phoneController = TextEditingController(text: existingPlace?.phone ?? '');
    _websiteController = TextEditingController(
      text: existingPlace?.website ?? '',
    );
    _descriptionController = TextEditingController(
      text: existingPlace?.description ?? '',
    );

    if (existingPlace != null) {
      _selectedLocation = existingPlace.location;
      _mapCenter = existingPlace.location;
      final bytes = existingPlace.imageBytes;
      if (bytes != null) {
        _selectedImageBytes = bytes;
        _selectedImageFileName = 'Current photo';
        _imageRemoved = false;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(existingPlace.location, 17);
      });
    } else {
      _selectedLocation = widget.initialLocation;
      _mapCenter = widget.initialLocation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setSelectedLocation(widget.initialLocation, updateAddress: true);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.removeListener(_handleCategoryChanged);
    _categoryController.dispose();
    _addressController.dispose();
    _locatedWithinController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _descriptionController.dispose();
    _addressDebounce?.cancel();
    _categoryFocusNode.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  void _handleCategoryChanged() {
    if (!mounted) return;
    setState(() {
      _quickCategorySelection = _deriveQuickSelection(
        _categoryController.text,
        previous: _quickCategorySelection,
      );
    });
  }

  String? _deriveQuickSelection(String value, {String? previous}) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'home') {
      return 'home';
    }
    if (normalized == 'apartment') {
      return 'apartment';
    }
    if (normalized.isEmpty) {
      return previous == 'other' ? 'other' : null;
    }
    return 'other';
  }

  void _onAddressQueryChanged(String value) {
    if (_isHandlingAddressSelection) {
      return;
    }

    _addressDebounce?.cancel();
    final trimmed = value.trim();

    _reverseGeocodeRequestId++;

    if (trimmed.length < 3) {
      _addressRequestId++;
      setState(() {
        _addressOptions = <_AddressSuggestion>[];
        _addressLookupMessage = null;
        _addressLookupIsError = false;
        _isFetchingAddressOptions = false;
        _isReverseGeocoding = false;
      });
      return;
    }

    setState(() {
      _addressOptions = <_AddressSuggestion>[];
      _addressLookupMessage = null;
      _addressLookupIsError = false;
      _isReverseGeocoding = false;
    });

    _addressDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchAddressSuggestions(trimmed);
    });
  }

  Future<void> _fetchAddressSuggestions(String query) async {
    final requestId = ++_addressRequestId;

    setState(() {
      _isFetchingAddressOptions = true;
      _addressLookupMessage = null;
      _addressLookupIsError = false;
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '5',
        'autocomplete': '1',
        'dedupe': '1',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'balumohol-app/1.0 (balumohol@example.com)',
        },
      );

      if (!mounted || requestId != _addressRequestId) {
        return;
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final suggestions = data
            .whereType<Map<String, dynamic>>()
            .map(_AddressSuggestion.fromJson)
            .toList(growable: false);

        setState(() {
          _addressOptions = suggestions;
          if (suggestions.isEmpty) {
            _addressLookupMessage = 'No matching addresses found.';
            _addressLookupIsError = false;
          } else {
            _addressLookupMessage = null;
            _addressLookupIsError = false;
          }
        });
      } else {
        setState(() {
          _addressOptions = <_AddressSuggestion>[];
          _addressLookupMessage =
              'Unable to load address suggestions. Please try again.';
          _addressLookupIsError = true;
        });
      }
    } catch (_) {
      if (!mounted || requestId != _addressRequestId) {
        return;
      }
      setState(() {
        _addressOptions = <_AddressSuggestion>[];
        _addressLookupMessage =
            'Unable to load address suggestions. Please check your connection.';
        _addressLookupIsError = true;
      });
    } finally {
      if (!mounted || requestId != _addressRequestId) {
        return;
      }
      setState(() {
        _isFetchingAddressOptions = false;
      });
    }
  }

  void _handleAddressSuggestionSelected(_AddressSuggestion suggestion) {
    _addressDebounce?.cancel();
    _isHandlingAddressSelection = true;
    _addressController.value = TextEditingValue(
      text: suggestion.displayName,
      selection: TextSelection.collapsed(offset: suggestion.displayName.length),
    );
    _isHandlingAddressSelection = false;

    _addressRequestId++;
    _reverseGeocodeRequestId++;

    _setSelectedLocation(suggestion.location, updateAddress: false);

    setState(() {
      _addressOptions = <_AddressSuggestion>[];
      _addressLookupMessage = null;
      _addressLookupIsError = false;
      _isFetchingAddressOptions = false;
      _isReverseGeocoding = false;
    });

    _mapController.move(suggestion.location, _mapController.camera.zoom);
  }

  InputDecoration _buildFieldDecoration({
    required String label,
    String? hint,
    Widget? suffixIcon,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(12);
    final baseBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    final fillColor = Color.alphaBlend(
      colorScheme.surfaceVariant.withOpacity(
        theme.brightness == Brightness.dark ? 0.24 : 0.1,
      ),
      colorScheme.surface,
    );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: fillColor,
      suffixIcon: suffixIcon,
      border: baseBorder,
      enabledBorder: baseBorder,
      focusedBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    );
  }

  Widget _buildCategoryQuickOptions(ThemeData theme) {
    final selection = _quickCategorySelection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick category options',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.home_outlined),
              label: const Text('Home'),
              selected: selection == 'home',
              onSelected: (selected) {
                if (!selected) return;
                if (_categoryController.text.trim().toLowerCase() != 'home') {
                  _categoryController.text = 'Home';
                }
                FocusScope.of(context).unfocus();
              },
            ),
            ChoiceChip(
              avatar: const Icon(Icons.apartment),
              label: const Text('Apartment'),
              selected: selection == 'apartment',
              onSelected: (selected) {
                if (!selected) return;
                if (_categoryController.text.trim().toLowerCase() !=
                    'apartment') {
                  _categoryController.text = 'Apartment';
                }
                FocusScope.of(context).unfocus();
              },
            ),
            ChoiceChip(
              avatar: const Icon(Icons.create_outlined),
              label: const Text('Other'),
              selected: selection == 'other',
              onSelected: (selected) {
                if (!selected) {
                  if (_categoryController.text.trim().isEmpty) {
                    setState(() {
                      _quickCategorySelection = null;
                    });
                  }
                  return;
                }
                setState(() {
                  _quickCategorySelection = 'other';
                });
                final currentValue = _categoryController.text.trim().toLowerCase();
                if (currentValue == 'home' || currentValue == 'apartment') {
                  _categoryController.clear();
                }
                FocusScope.of(context).requestFocus(_categoryFocusNode);
              },
            ),
          ],
        ),
        if (selection == 'other')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Type a custom category above.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  void _setSelectedLocation(LatLng point, {bool updateAddress = true}) {
    setState(() {
      _selectedLocation = point;
      _mapCenter = point;
      _addressLookupMessage = null;
      _addressLookupIsError = false;
    });
    if (updateAddress) {
      _reverseGeocode(point);
    }
  }

  void _useMapCenter() {
    _setSelectedLocation(_mapCenter, updateAddress: true);
  }

  Future<void> _reverseGeocode(LatLng point) async {
    final requestId = ++_reverseGeocodeRequestId;

    setState(() {
      _isReverseGeocoding = true;
      _addressOptions = <_AddressSuggestion>[];
      _addressLookupMessage = 'Fetching address for selected location...';
      _addressLookupIsError = false;
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'zoom': '18',
      });

      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'balumohol-app/1.0 (balumohol@example.com)',
        },
      );

      if (!mounted || requestId != _reverseGeocodeRequestId) {
        return;
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final displayName = data['display_name'] as String? ?? '';

        if (displayName.isNotEmpty) {
          _addressRequestId++;
          _isHandlingAddressSelection = true;
          _addressController.value = TextEditingValue(
            text: displayName,
            selection: TextSelection.collapsed(offset: displayName.length),
          );
          _isHandlingAddressSelection = false;
          setState(() {
            _addressLookupMessage = null;
            _addressLookupIsError = false;
          });
        } else {
          setState(() {
            _addressLookupMessage =
                'No address details found for this location.';
            _addressLookupIsError = false;
          });
        }
      } else {
        setState(() {
          _addressLookupMessage =
              'Unable to determine the address for the selected location.';
          _addressLookupIsError = true;
        });
      }
    } catch (_) {
      if (!mounted || requestId != _reverseGeocodeRequestId) {
        return;
      }
      setState(() {
        _addressLookupMessage =
            'Unable to determine the address. Please check your connection.';
        _addressLookupIsError = true;
      });
    } finally {
      if (!mounted || requestId != _reverseGeocodeRequestId) {
        return;
      }
      setState(() {
        _isReverseGeocoding = false;
      });
    }
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
                        (category) => category.toLowerCase().contains(
                          searchQuery.toLowerCase(),
                        ),
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
                          child: Center(child: Text('No categories found.')),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: matches.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final category = matches[index];
                              return ListTile(
                                title: Text(category),
                                onTap: () =>
                                    Navigator.of(context).pop(category),
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
        _imageRemoved = false;
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
      _imageRemoved = true;
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

    final existingPlace = widget.existingPlace;
    final place = CustomPlace(
      name: _nameController.text.trim(),
      category: _categoryController.text.trim(),
      address: _addressController.text.trim(),
      location: location,
      locatedWithin: _locatedWithinController.text.emptyToNull(),
      phone: _phoneController.text.emptyToNull(),
      website: _websiteController.text.emptyToNull(),
      description: _descriptionController.text.emptyToNull(),
      createdAt: existingPlace?.createdAt ?? DateTime.now(),
      imageBase64: _selectedImageBytes != null
          ? base64Encode(_selectedImageBytes!)
          : (_imageRemoved ? null : existingPlace?.imageBase64),
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

    final isEditing = widget.existingPlace != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit place' : 'Add place')),
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
                                  _setSelectedLocation(point);
                                },
                                onMapEvent: (event) {
                                  _mapCenter = _mapController.camera.center;
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://{s}.google.com/vt/lyrs=s,h&x={x}&y={y}&z={z}',
                                  subdomains: ['mt0', 'mt1', 'mt2', 'mt3'],
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
                          decoration: _buildFieldDecoration(
                            label: 'Place name (required)',
                            hint: 'e.g. Rahman Traders',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: _validateRequired,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _categoryController,
                          focusNode: _categoryFocusNode,
                          decoration: _buildFieldDecoration(
                            label: 'Category (required)',
                            hint: 'e.g. Grocery store',
                            suffixIcon: IconButton(
                              tooltip: 'Browse categories',
                              icon: const Icon(Icons.list_alt),
                              onPressed: _showCategoryPicker,
                            ),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: _validateRequired,
                        ),
                        const SizedBox(height: 8),
                        _buildCategoryQuickOptions(theme),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, fieldConstraints) {
                            return RawAutocomplete<_AddressSuggestion>(
                              focusNode: _addressFocusNode,
                              textEditingController: _addressController,
                              displayStringForOption: (option) =>
                                  option.displayName,
                              optionsBuilder: (textEditingValue) {
                                final trimmed = textEditingValue.text.trim();
                                if (trimmed.length < 3) {
                                  return const Iterable<
                                    _AddressSuggestion
                                  >.empty();
                                }
                                return _addressOptions;
                              },
                              onSelected: _handleAddressSuggestionSelected,
                              fieldViewBuilder:
                                  (
                                    context,
                                    textEditingController,
                                    focusNode,
                                    onFieldSubmitted,
                                  ) {
                                    return TextFormField(
                                      controller: textEditingController,
                                      focusNode: focusNode,
                                      decoration: _buildFieldDecoration(
                                        label: 'Address (required)',
                                        hint:
                                            'Street, village, or house number',
                                        suffixIcon:
                                            (_isFetchingAddressOptions ||
                                                _isReverseGeocoding)
                                            ? const Padding(
                                                padding: EdgeInsets.all(12),
                                                child: SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              )
                                            : const Icon(Icons.place_outlined),
                                      ),
                                      textInputAction: TextInputAction.next,
                                      validator: _validateRequired,
                                      onChanged: _onAddressQueryChanged,
                                      onFieldSubmitted: (_) =>
                                          onFieldSubmitted(),
                                    );
                                  },
                              optionsViewBuilder:
                                  (context, onSelected, options) {
                                    if (options.isEmpty) {
                                      return const SizedBox.shrink();
                                    }

                                    return Align(
                                      alignment: Alignment.topLeft,
                                      child: Material(
                                        elevation: 6,
                                        borderRadius: BorderRadius.circular(12),
                                        clipBehavior: Clip.antiAlias,
                                        child: SizedBox(
                                          width: fieldConstraints.maxWidth,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxHeight: 240,
                                            ),
                                            child: ListView.separated(
                                              padding: EdgeInsets.zero,
                                              itemCount: options.length,
                                              separatorBuilder: (_, __) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, index) {
                                                final option = options
                                                    .elementAt(index);
                                                return ListTile(
                                                  leading: const Icon(
                                                    Icons.place_outlined,
                                                  ),
                                                  title: Text(
                                                    option.displayName,
                                                  ),
                                                  onTap: () =>
                                                      onSelected(option),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                            );
                          },
                        ),
                        if (_addressLookupMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _addressLookupMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _addressLookupIsError
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _locatedWithinController,
                          decoration: _buildFieldDecoration(
                            label: 'Located within (optional)',
                            hint: 'e.g. Market complex',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          decoration: _buildFieldDecoration(
                            label: 'Phone (optional)',
                            hint: 'e.g. 017XXXXXXXX',
                          ),
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _websiteController,
                          decoration: _buildFieldDecoration(
                            label: 'Website (optional)',
                            hint: 'e.g. https://example.com',
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
                          decoration: _buildFieldDecoration(
                            label: 'Additional details (optional)',
                            hint: 'Description, opening hours, notes',
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
                            label: Text(
                              isEditing ? 'Update place' : 'Save place',
                            ),
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
