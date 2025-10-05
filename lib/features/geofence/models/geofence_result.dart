import 'package:balumohol/core/language/localized_text.dart';

class GeofenceResult {
  const GeofenceResult({
    required this.inside,
    required this.statusMessage,
  });

  final bool inside;
  final LocalizedText statusMessage;
}
