import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';

class GpxService {
  // 从 assets 读取 GPX 文件
  static Future<Gpx?> loadGpxFromAssets(String assetPath) async {
    try {
      final xmlString = await rootBundle.loadString(assetPath);
      final gpx = GpxReader().fromString(xmlString);
      return gpx;
    } catch (e) {
      print('Error loading GPX from assets: $e');
      return null;
    }
  }

  // 从文件系统读取 GPX 文件
  static Future<Gpx?> loadGpxFromFile(String filePath) async {
    try {
      final file = File(filePath);
      final xmlString = await file.readAsString();
      final gpx = GpxReader().fromString(xmlString);
      return gpx;
    } catch (e) {
      print('Error loading GPX from file: $e');
      return null;
    }
  }

  // 数据预处理：移除重复点、按时间排序
  static List<Map<String, dynamic>> preprocessPoints(List<Map<String, dynamic>> points) {
    if (points.isEmpty) return [];
    
    // 1. 移除时间戳重复或完全相同经纬度的点
    final cleaned = <Map<String, dynamic>>[];
    for (int i = 0; i < points.length; i++) {
      if (i == 0) {
        cleaned.add(points[i]);
        continue;
      }
      
      final prev = points[i - 1];
      final curr = points[i];
      
      // 检查是否重复
      final sameLocation = (prev['lat'] == curr['lat'] && prev['lon'] == curr['lon']);
      final sameTime = (prev['time'] != null && curr['time'] != null && 
                        prev['time'] == curr['time']);
      
      if (!sameLocation && !sameTime) {
        cleaned.add(curr);
      }
    }
    
    // 2. 依时间排序
    cleaned.sort((a, b) {
      if (a['time'] == null || b['time'] == null) return 0;
      return (a['time'] as DateTime).compareTo(b['time'] as DateTime);
    });
    
    return cleaned;
  }
  
  // 过滤异常速度点（登山场景）
  static List<Map<String, dynamic>> filterAbnormalSpeed(List<Map<String, dynamic>> points) {
    if (points.length < 2) return points;
    
    const maxSpeed = 8.0 / 3.6; // 8 km/h = 2.22 m/s（登山最大合理速度）
    const distance = Distance();
    
    final filtered = <Map<String, dynamic>>[points[0]];
    
    for (int i = 1; i < points.length; i++) {
      final prev = filtered.last;
      final curr = points[i];
      
      // 计算距离和时间间隔
      final p1 = LatLng(prev['lat'] as double, prev['lon'] as double);
      final p2 = LatLng(curr['lat'] as double, curr['lon'] as double);
      final dist = distance.as(LengthUnit.Meter, p1, p2);
      
      if (prev['time'] != null && curr['time'] != null) {
        final timeInterval = (curr['time'] as DateTime).difference(prev['time'] as DateTime).inSeconds.toDouble();
        
        if (timeInterval > 0) {
          final speed = dist / timeInterval;
          
          // 只保留速度合理的点
          if (speed <= maxSpeed) {
            filtered.add(curr);
          }
        } else {
          filtered.add(curr);
        }
      } else {
        filtered.add(curr);
      }
    }
    
    return filtered;
  }
  
  // 经纬度平滑（加权移动平均 - 中心点权重更高）
  static List<Map<String, dynamic>> smoothCoordinatesWeighted(List<Map<String, dynamic>> points, double strength) {
    if (points.length < 3) return points;
    
    final smoothed = <Map<String, dynamic>>[];
    
    for (int i = 0; i < points.length; i++) {
      if (i == 0 || i == points.length - 1) {
        // 首尾点不平滑
        smoothed.add(points[i]);
        continue;
      }
      
      // 加权平滑：strength控制平滑程度 (0=不平滑, 1=完全平滑)
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];
      
      final smoothLat = (curr['lat'] as double) * (1 - strength) + 
                       (((prev['lat'] as double) + (next['lat'] as double)) / 2) * strength;
      final smoothLon = (curr['lon'] as double) * (1 - strength) + 
                       (((prev['lon'] as double) + (next['lon'] as double)) / 2) * strength;
      
      smoothed.add({
        'lat': smoothLat,
        'lon': smoothLon,
        'ele': curr['ele'],
        'time': curr['time'],
      });
    }
    
    return smoothed;
  }
  
  // 经纬度平滑（移动平均）
  static List<Map<String, dynamic>> smoothCoordinates(List<Map<String, dynamic>> points, int windowSize) {
    if (points.length < windowSize) return points;
    
    final smoothed = <Map<String, dynamic>>[];
    
    for (int i = 0; i < points.length; i++) {
      final start = (i - windowSize ~/ 2).clamp(0, points.length - 1);
      final end = (i + windowSize ~/ 2 + 1).clamp(0, points.length);
      
      double sumLat = 0.0;
      double sumLon = 0.0;
      int count = 0;
      
      for (int j = start; j < end; j++) {
        sumLat += points[j]['lat'] as double;
        sumLon += points[j]['lon'] as double;
        count++;
      }
      
      smoothed.add({
        'lat': sumLat / count,
        'lon': sumLon / count,
        'ele': points[i]['ele'],
        'time': points[i]['time'],
      });
    }
    
    return smoothed;
  }
  
  // 高度平滑（移动平均）
  static List<Map<String, dynamic>> smoothElevation(List<Map<String, dynamic>> points, int windowSize) {
    if (points.length < windowSize) return points;
    
    final smoothed = <Map<String, dynamic>>[];
    
    for (int i = 0; i < points.length; i++) {
      final start = (i - windowSize ~/ 2).clamp(0, points.length - 1);
      final end = (i + windowSize ~/ 2 + 1).clamp(0, points.length);
      
      double sumEle = 0.0;
      int count = 0;
      
      for (int j = start; j < end; j++) {
        sumEle += points[j]['ele'] as double;
        count++;
      }
      
      smoothed.add({
        'lat': points[i]['lat'],
        'lon': points[i]['lon'],
        'ele': sumEle / count,
        'time': points[i]['time'],
      });
    }
    
    return smoothed;
  }
  static List<Map<String, dynamic>> getTrackPointsWithElevation(Gpx gpx) {
    final points = <Map<String, dynamic>>[];
    
    if (gpx.trks.isNotEmpty) {
      for (var track in gpx.trks) {
        for (var segment in track.trksegs) {
          for (var point in segment.trkpts) {
            if (point.lat != null && point.lon != null) {
              points.add({
                'lat': point.lat!,
                'lon': point.lon!,
                'ele': point.ele ?? 0.0,
                'time': point.time,
              });
            }
          }
        }
      }
    }
    
    return points;
  }

  // 获取 GPX 轨迹点列表
  static List<LatLng> getTrackPoints(Gpx gpx) {
    final points = <LatLng>[];
    
    if (gpx.trks.isNotEmpty) {
      for (var track in gpx.trks) {
        for (var segment in track.trksegs) {
          for (var point in segment.trkpts) {
            if (point.lat != null && point.lon != null) {
              points.add(LatLng(point.lat!, point.lon!));
            }
          }
        }
      }
    }
    
    return points;
  }

  // 获取 GPX 路线点列表
  static List<LatLng> getRoutePoints(Gpx gpx) {
    final points = <LatLng>[];
    
    if (gpx.rtes.isNotEmpty) {
      for (var route in gpx.rtes) {
        for (var point in route.rtepts) {
          if (point.lat != null && point.lon != null) {
            points.add(LatLng(point.lat!, point.lon!));
          }
        }
      }
    }
    
    return points;
  }

  // 获取所有点（轨迹点 + 路线点）
  static List<LatLng> getAllPoints(Gpx gpx) {
    final points = <LatLng>[];
    points.addAll(getTrackPoints(gpx));
    points.addAll(getRoutePoints(gpx));
    return points;
  }

  // 计算路线边界
  static LatLngBounds? calculateBounds(List<LatLng> points) {
    if (points.isEmpty) return null;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    }

    return LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
  }

  // 获取路线中心点
  static LatLng? getCenter(List<LatLng> points) {
    if (points.isEmpty) return null;

    final bounds = calculateBounds(points);
    if (bounds == null) return null;

    return LatLng(
      (bounds.north + bounds.south) / 2,
      (bounds.east + bounds.west) / 2,
    );
  }

  // 计算总距离（公里）- 使用平滑后的数据
  static double calculateTotalDistance(List<Map<String, dynamic>> points) {
    if (points.length < 2) return 0.0;

    double totalDistanceMeters = 0.0;
    const distance = Distance();

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = LatLng(points[i]['lat'] as double, points[i]['lon'] as double);
      final p2 = LatLng(points[i + 1]['lat'] as double, points[i + 1]['lon'] as double);
      
      final segmentDistance = distance.as(LengthUnit.Meter, p1, p2);
      totalDistanceMeters += segmentDistance;
    }
    
    return totalDistanceMeters / 1000.0; // 转换为公里
  }
  
  // 计算总爬升高度（米）- 使用可配置阈值
  static double calculateAscentWithThreshold(List<Map<String, dynamic>> points, double threshold) {
    if (points.length < 2) return 0.0;

    double totalAscent = 0.0;

    for (int i = 1; i < points.length; i++) {
      final elevationGain = (points[i]['ele'] as double) - (points[i - 1]['ele'] as double);
      
      // 只累加超过阈值的正向爬升
      if (elevationGain >= threshold) {
        totalAscent += elevationGain;
      }
    }
    
    return totalAscent;
  }
  
  // 计算总爬升高度（米）- 使用平滑后的高度和阈值
  static double calculateTotalAscent(List<Map<String, dynamic>> points) {
    return calculateAscentWithThreshold(points, 0.5); // 使用0.5m阈值
  }
  
  // 获取路线统计数据
  static Map<String, dynamic> getRouteStats(Gpx gpx) {
    // 1. 获取原始数据
    final rawPoints = getTrackPointsWithElevation(gpx);
    print('原始点数: ${rawPoints.length}');
    
    // 2. 数据预处理：移除重复点、按时间排序
    final cleanedPoints = preprocessPoints(rawPoints);
    print('清洗后点数: ${cleanedPoints.length}');
    
    // 3. 过滤异常速度点
    final speedFiltered = filterAbnormalSpeed(cleanedPoints);
    print('速度过滤后点数: ${speedFiltered.length}');
    
    // 4. 经纬度加权平滑（strength=0.5，中度平滑，目标接近2.46km）
    final smoothedCoords = smoothCoordinatesWeighted(speedFiltered, 0.3);
    print('经纬度平滑完成');
    
    // 5. 高度平滑（5点窗口）
    final smoothedElevation = smoothElevation(smoothedCoords, 5);
    print('高度平滑完成');
    
    // 6. 计算距离和爬升（爬升阈值0.5m）
    final distance = calculateTotalDistance(smoothedCoords);
    final ascent = calculateAscentWithThreshold(smoothedElevation, 0.5);
    
    print('计算结果:');
    print('  距离: ${distance.toStringAsFixed(2)}km');
    print('  爬升: ${ascent.toStringAsFixed(0)}m');
    
    // 7. 计算时长
    Duration? duration;
    if (rawPoints.isNotEmpty && rawPoints.first['time'] != null && rawPoints.last['time'] != null) {
      duration = (rawPoints.last['time'] as DateTime).difference(rawPoints.first['time'] as DateTime);
      print('  时长: ${duration.inHours}h${duration.inMinutes % 60}m');
    }
    
    return {
      'distance': distance,
      'ascent': ascent,
      'duration': duration,
      'pointCount': smoothedElevation.length,
    };
  }
}

