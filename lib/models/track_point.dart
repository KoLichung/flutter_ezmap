class TrackPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime timestamp;
  final double? speed;

  TrackPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.timestamp,
    this.speed,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'timestamp': timestamp.toIso8601String(),
      'speed': speed,
    };
  }

  factory TrackPoint.fromJson(Map<String, dynamic> json) {
    return TrackPoint(
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      altitude: json['altitude'] as double?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      speed: json['speed'] as double?,
    );
  }
}

