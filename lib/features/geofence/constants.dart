import 'package:flutter/material.dart';

const int sampleBufferSize = 8;
const Duration historyInterval = Duration(seconds: 10);
const int maxHistoryEntries = 200;
const String historyStorageKey = 'locationHistory';
const Duration sampleRetentionDuration = Duration(seconds: 12);
const double defaultFollowZoom = 17;
const String customPlacesStorageKey = 'customPlaces';

const List<String> placeCategories = [
  'Restaurant',
  'Cafe',
  'Coffee shop',
  'Bakery',
  'Fast food restaurant',
  'Grocery store',
  'Supermarket',
  'Convenience store',
  'Clothing store',
  'Electronics store',
  'Pharmacy',
  'Hospital',
  'Clinic',
  'School',
  'College',
  'University',
  'Library',
  'Hotel',
  'Guest house',
  'ATM',
  'Bank',
  'Fuel station',
  'Car repair',
  'Parking',
  'Park',
  'Playground',
  'Gym',
  'Stadium',
  'Movie theater',
  'Shopping mall',
  'Hardware store',
  'Home goods store',
  'Furniture store',
  'Jewelry store',
  'Salon',
  'Spa',
  'Barbershop',
  'Mosque',
  'Temple',
  'Church',
  'Government office',
  'Police station',
  'Post office',
  'Courier service',
  'Bus station',
  'Train station',
  'Airport',
  'Tourist attraction',
  'Museum',
  'Zoo',
  'Factory',
  'Warehouse',
  'Farm',
  'Water treatment plant',
  'Construction site',
  'Community center',
  'Event venue',
  'Coworking space',
  'Technology park',
  'Religious institution',
  'Sports club',
  'Medical store',
  'Diagnostic center',
  'Pet store',
  'Veterinary clinic',
];

const preferredPropertyOrder = <String>[
  'plot_number',
  'mouza_name',
  'upazila',
  'Remarks',
  'Shape_Length',
  'Shape_Area',
];

final polygonBaseBorderColor = Colors.blue.shade600;
final polygonSelectedBorderColor = Colors.orange.shade700;
final polygonBaseFillColor = const Color(0xFF42A5F5).withOpacity(0.2);
final polygonSelectedFillColor = const Color(0xFFFFB74D).withOpacity(0.35);
