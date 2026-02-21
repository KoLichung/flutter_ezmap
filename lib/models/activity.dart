import 'track_point.dart';
import 'waypoint.dart';

class Activity {
  final String id;
  final String name;
  final DateTime startTime;
  DateTime? endTime;
  final List<TrackPoint> trackPoints;
  final List<Waypoint> waypoints;
  double totalDistance;
  double totalAscent;
  double totalDescent;
  double maxSpeed;
  double avgSpeed;
  Duration movingTime;
  Duration totalTime;
  String? gpxFilePath;

  Activity({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    required this.trackPoints,
    List<Waypoint>? waypoints,
    this.totalDistance = 0,
    this.totalAscent = 0,
    this.totalDescent = 0,
    this.maxSpeed = 0,
    this.avgSpeed = 0,
    this.movingTime = Duration.zero,
    this.totalTime = Duration.zero,
    this.gpxFilePath,
  }) : waypoints = waypoints ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'trackPoints': trackPoints.map((e) => e.toJson()).toList(),
      'waypoints': waypoints.map((e) => e.toJson()).toList(),
      'totalDistance': totalDistance,
      'totalAscent': totalAscent,
      'totalDescent': totalDescent,
      'maxSpeed': maxSpeed,
      'avgSpeed': avgSpeed,
      'movingTime': movingTime.inSeconds,
      'totalTime': totalTime.inSeconds,
      'gpxFilePath': gpxFilePath,
    };
  }

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: json['id'] as String,
      name: json['name'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      trackPoints: (json['trackPoints'] as List)
          .map((e) => TrackPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      waypoints: (json['waypoints'] as List?)?.map((e) => Waypoint.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      totalDistance: (json['totalDistance'] as num).toDouble(),
      totalAscent: (json['totalAscent'] as num).toDouble(),
      totalDescent: (json['totalDescent'] as num).toDouble(),
      maxSpeed: (json['maxSpeed'] as num).toDouble(),
      avgSpeed: (json['avgSpeed'] as num).toDouble(),
      movingTime: Duration(seconds: json['movingTime'] as int),
      totalTime: Duration(seconds: json['totalTime'] as int),
      gpxFilePath: json['gpxFilePath'] as String?,
    );
  }
}

