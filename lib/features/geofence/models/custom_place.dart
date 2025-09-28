import 'dart:convert';
import 'dart:typed_data';

import 'package:balumohol/core/utils/formatting.dart';
import 'package:balumohol/core/utils/string_extensions.dart';
import 'package:latlong2/latlong.dart';

class CustomPlace {
  const CustomPlace({
    required this.name,
    required this.category,
    required this.address,
    required this.location,
    this.locatedWithin,
    this.phone,
    this.website,
    this.description,
    required this.createdAt,
    this.imageBase64,
  });

  factory CustomPlace.fromJson(Map<String, dynamic> json) {
    final latitude = (json['lat'] as num?)?.toDouble();
    final longitude = (json['lng'] as num?)?.toDouble();
    final createdAtMs = json['createdAt'] as int?;

    return CustomPlace(
      name: (json['name'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? '').trim(),
      address: (json['address'] as String? ?? '').trim(),
      location: LatLng(latitude ?? 0, longitude ?? 0),
      locatedWithin: (json['locatedWithin'] as String?).emptyToNull(),
      phone: (json['phone'] as String?).emptyToNull(),
      website: (json['website'] as String?).emptyToNull(),
      description: (json['description'] as String?).emptyToNull(),
      createdAt: createdAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
          : DateTime.now(),
      imageBase64: (json['image'] as String?).emptyToNull(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'address': address,
      'lat': location.latitude,
      'lng': location.longitude,
      'locatedWithin': locatedWithin,
      'phone': phone,
      'website': website,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'image': imageBase64,
    };
  }

  final String name;
  final String category;
  final String address;
  final LatLng location;
  final String? locatedWithin;
  final String? phone;
  final String? website;
  final String? description;
  final DateTime createdAt;
  final String? imageBase64;

  Uint8List? get imageBytes {
    final data = imageBase64;
    if (data == null || data.isEmpty) {
      return null;
    }
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  List<MapEntry<String, String>> details() {
    final entries = <MapEntry<String, String>>[
      MapEntry('Category', category),
      MapEntry('Address', address),
    ];

    if (locatedWithin != null && locatedWithin!.isNotEmpty) {
      entries.add(MapEntry('Located within', locatedWithin!));
    }
    if (phone != null && phone!.isNotEmpty) {
      entries.add(MapEntry('Phone', phone!));
    }
    if (website != null && website!.isNotEmpty) {
      entries.add(MapEntry('Website', website!));
    }
    if (description != null && description!.isNotEmpty) {
      entries.add(MapEntry('Details', description!));
    }
    entries.add(
      MapEntry('Added on', formatTimestampEnglish(createdAt.millisecondsSinceEpoch)),
    );
    entries.add(
      MapEntry('Coordinates', formatLatLng(location, fractionDigits: 6)),
    );
    return entries;
  }
}
