import 'package:latlong2/latlong.dart';

class PolygonFeature {
  const PolygonFeature({
    required this.id,
    required this.outer,
    required this.holes,
    required this.properties,
  });

  final String id;
  final List<LatLng> outer;
  final List<List<LatLng>> holes;
  final Map<String, dynamic> properties;
}
