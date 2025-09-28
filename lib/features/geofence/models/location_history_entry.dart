class LocationHistoryEntry {
  const LocationHistoryEntry({
    required this.latitude,
    required this.longitude,
    required this.inside,
    required this.timestampMs,
    required this.accuracy,
  });

  factory LocationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LocationHistoryEntry(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      inside: json['inside'] as bool,
      timestampMs: json['timestamp'] as int,
      accuracy: (json['accuracy'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': latitude,
      'lng': longitude,
      'inside': inside,
      'timestamp': timestampMs,
      'accuracy': accuracy,
    };
  }

  final double latitude;
  final double longitude;
  final bool inside;
  final int timestampMs;
  final double accuracy;
}
