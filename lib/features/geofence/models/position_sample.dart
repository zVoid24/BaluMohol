class PositionSample {
  const PositionSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestampMs,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final int timestampMs;
}
