import 'package:flutter/material.dart';

class PlaceCategoryStyle {
  const PlaceCategoryStyle({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;
}

PlaceCategoryStyle styleForCategory(String category) {
  final normalized = category.toLowerCase();

  if (_containsAny(normalized, const [
    'hospital',
    'clinic',
    'medical',
    'diagnostic',
    'pharmacy',
    'health',
  ])) {
    return PlaceCategoryStyle(
      icon: Icons.local_hospital,
      color: Colors.redAccent.shade400,
    );
  }

  if (_containsAny(normalized, const [
    'school',
    'college',
    'university',
    'library',
    'education',
  ])) {
    return const PlaceCategoryStyle(
      icon: Icons.school,
      color: Color(0xFF3949AB),
    );
  }

  if (_containsAny(normalized, const [
    'restaurant',
    'cafe',
    'coffee',
    'bakery',
    'food',
    'bar',
  ])) {
    return PlaceCategoryStyle(
      icon: Icons.restaurant,
      color: Colors.orange.shade600,
    );
  }

  if (_containsAny(normalized, const [
    'shop',
    'store',
    'market',
    'mall',
    'shopping',
    'hardware',
    'electronics',
    'jewelry',
    'furniture',
  ])) {
    return PlaceCategoryStyle(
      icon: Icons.storefront,
      color: Colors.blueGrey.shade600,
    );
  }

  if (_containsAny(normalized, const [
    'hotel',
    'guest house',
    'resort',
    'hostel',
  ])) {
    return const PlaceCategoryStyle(
      icon: Icons.hotel,
      color: Color(0xFF00838F),
    );
  }

  if (_containsAny(normalized, const [
    'bank',
    'atm',
    'finance',
  ])) {
    return const PlaceCategoryStyle(
      icon: Icons.account_balance,
      color: Color(0xFF00695C),
    );
  }

  if (_containsAny(normalized, const [
    'fuel',
    'gas',
    'petrol',
    'parking',
    'car',
    'transport',
    'bus',
    'train',
    'airport',
  ])) {
    return PlaceCategoryStyle(
      icon: Icons.local_gas_station,
      color: Colors.deepPurple.shade500,
    );
  }

  if (_containsAny(normalized, const [
    'park',
    'playground',
    'stadium',
    'gym',
    'sports',
    'zoo',
    'tourist',
    'museum',
    'theater',
  ])) {
    return PlaceCategoryStyle(
      icon: Icons.park,
      color: Colors.green.shade600,
    );
  }

  if (_containsAny(normalized, const [
    'mosque',
    'temple',
    'church',
    'religious',
  ])) {
    return const PlaceCategoryStyle(
      icon: Icons.account_balance,
      color: Color(0xFF6D4C41),
    );
  }

  if (_containsAny(normalized, const [
    'office',
    'government',
    'community',
    'event',
    'factory',
    'warehouse',
    'construction',
    'coworking',
    'technology',
  ])) {
    return PlaceCategoryStyle(
      icon: Icons.apartment,
      color: Colors.indigo.shade400,
    );
  }

  return PlaceCategoryStyle(
    icon: Icons.place,
    color: Colors.blue.shade600,
  );
}

bool _containsAny(String value, List<String> terms) {
  for (final term in terms) {
    if (value.contains(term)) {
      return true;
    }
  }
  return false;
}
