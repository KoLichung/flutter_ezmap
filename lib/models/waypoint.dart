class Waypoint {
  final String id;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime timestamp;
  final String? icon;

  Waypoint({
    required this.id,
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.timestamp,
    this.icon,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'timestamp': timestamp.toIso8601String(),
      'icon': icon,
    };
  }

  factory Waypoint.fromJson(Map<String, dynamic> json) {
    return Waypoint(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      altitude: json['altitude'] as double?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      icon: json['icon'] as String?,
    );
  }
}

