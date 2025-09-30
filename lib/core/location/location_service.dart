import 'package:geolocator/geolocator.dart';

/// Provides access to location related features in a decoupled manner so that
/// the rest of the codebase does not depend directly on the Geolocator
/// implementation.
abstract class LocationService {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<Position> getCurrentPosition({
    LocationSettings? settings,
    LocationAccuracy? desiredAccuracy,
    Duration? timeLimit,
  });

  Stream<Position> getPositionStream(LocationSettings settings);

  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  );

  double bearingBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  );
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  @override
  Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? settings,
    LocationAccuracy? desiredAccuracy,
    Duration? timeLimit,
  }) {
    if (settings != null) {
      return Geolocator.getCurrentPosition(
        locationSettings: settings,
        timeLimit: timeLimit,
      );
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: desiredAccuracy,
      timeLimit: timeLimit,
    );
  }

  @override
  Stream<Position> getPositionStream(LocationSettings settings) {
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  @override
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  @override
  double bearingBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.bearingBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }
}
