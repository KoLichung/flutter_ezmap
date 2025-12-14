import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import '../lib/services/gpx_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GPX 参数调优测试', () async {
    // 加载 GPX 文件
    final xmlString = await rootBundle.loadString('lib/test_files/合歡東峰.gpx');
    final gpx = GpxReader().fromString(xmlString);
    
    print('\n========================================');
    print('开始 GPX 数据处理参数调优');
    print('目标: 距离 2.46±0.05km, 爬升 308±5m');
    print('========================================\n');
    
    // 获取原始数据
    final rawPoints = GpxService.getTrackPointsWithElevation(gpx);
    print('📊 原始数据: ${rawPoints.length} 个点\n');
    
    // 步骤 1: 数据清洗
    final cleanedPoints = GpxService.preprocessPoints(rawPoints);
    print('步骤 1 - 数据清洗');
    print('  移除重复点: ${rawPoints.length - cleanedPoints.length} 个');
    print('  剩余点数: ${cleanedPoints.length}\n');
    
    // 步骤 2: 速度过滤 - 测试不同阈值
    print('步骤 2 - 速度过滤测试');
    for (var maxSpeed in [2.5, 3.0, 3.5, 4.0]) {
      final filtered = _filterBySpeed(cleanedPoints, maxSpeed);
      final dist = _calculateDistance(filtered);
      print('  速度阈值 ${maxSpeed} m/s (${(maxSpeed * 3.6).toStringAsFixed(1)} km/h): '
            '${filtered.length} 点, 距离 ${dist.toStringAsFixed(2)} km');
    }
    print('');
    
    // 步骤 3: 平滑窗口测试 - 更精细
    print('步骤 3 - 经纬度平滑窗口精细测试（目标: 2.43-2.49km）');
    final speedFiltered = _filterBySpeed(cleanedPoints, 3.0);
    
    print('  不同平滑程度的距离:');
    final distResults = <int, double>{};
    for (var window in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      final smoothed = window == 1 ? speedFiltered : GpxService.smoothCoordinates(speedFiltered, window);
      final dist = _calculateDistance(smoothed);
      distResults[window] = dist;
      final diff = (dist - 2.46).abs() * 1000;
      final status = diff <= 30 ? '✓ 符合' : '';
      print('  窗口 ${window.toString().padLeft(2)}: ${dist.toStringAsFixed(3)} km (误差 ${diff.toStringAsFixed(1).padLeft(5)}m) $status');
    }
    
    // 寻找可以插值的窗口范围
    print('\n  分析: 窗口1->2距离从 2.527 跳到 2.369，跨度 158m');
    print('        需要使用不同的平滑算法或调整实现');
    print('');
    
    // 步骤 4: 爬升阈值测试
    print('步骤 4 - 爬升阈值测试');
    final coordSmoothed = GpxService.smoothCoordinates(speedFiltered, 5);
    
    for (var eleWindow in [5, 7, 9, 11]) {
      final eleSmoothed = GpxService.smoothElevation(coordSmoothed, eleWindow);
      print('  高度平滑窗口 $eleWindow:');
      
      for (var threshold in [1.0, 1.5, 2.0, 2.5, 3.0]) {
        final ascent = _calculateAscent(eleSmoothed, threshold);
        print('    阈值 ${threshold}m: 爬升 ${ascent.toStringAsFixed(0)} m');
      }
      print('');
    }
    
    // 步骤 5: 精细搜索最佳组合（目标: 2.43-2.49km, 303-313m）
    print('步骤 5 - 精细搜索最佳组合');
    print('目标范围: 2.43-2.49km, 303-313m');
    print('----------------------------------------');
    
    var bestDiff = double.infinity;
    var bestConfig = '';
    var bestDistance = 0.0;
    var bestAscent = 0.0;
    var bestSpeed = 0.0;
    var bestCoordWin = 0;
    var bestEleWin = 0;
    var bestAscentThresh = 0.0;
    
    // 更精细的参数范围，重点测试经纬度窗口1-4
    for (var speedThreshold in [2.5, 3.0, 3.5]) {
      for (var coordWindow in [1, 2, 3, 4]) {
        for (var eleWindow in [3, 5, 7]) {
          for (var ascentThreshold in [0.5, 0.8, 1.0]) {
            final filtered = _filterBySpeed(cleanedPoints, speedThreshold);
            final coordSmoothed = coordWindow == 1 ? filtered : GpxService.smoothCoordinates(filtered, coordWindow);
            final eleSmoothed = GpxService.smoothElevation(coordSmoothed, eleWindow);
            
            final dist = _calculateDistance(coordSmoothed);
            final ascent = _calculateAscent(eleSmoothed, ascentThreshold);
            
            // 计算与目标的差距 (2.46km, 308m)
            final distDiff = (dist - 2.46).abs();
            final ascentDiff = (ascent - 308).abs();
            
            // 严格要求距离在 ±30m 内
            if (distDiff <= 0.03) {
              final totalDiff = distDiff * 500 + ascentDiff;
              
              if (totalDiff < bestDiff) {
                bestDiff = totalDiff;
                bestSpeed = speedThreshold;
                bestCoordWin = coordWindow;
                bestEleWin = eleWindow;
                bestAscentThresh = ascentThreshold;
                bestDistance = dist;
                bestAscent = ascent;
              }
            }
          }
        }
      }
    }
    
    if (bestDiff < double.infinity) {
      bestConfig = '速度≤${bestSpeed}m/s (${(bestSpeed * 3.6).toStringAsFixed(1)}km/h), '
                   '经纬度窗口${bestCoordWin}点, 高度窗口${bestEleWin}点, 爬升阈值${bestAscentThresh}m';
      
      print('🎯 最佳配置（距离符合 ±30m）:');
      print('  $bestConfig');
      print('  结果: ${bestDistance.toStringAsFixed(3)} km, ${bestAscent.toStringAsFixed(0)} m');
      print('  目标: 2.460 km, 308 m');
      print('  误差: 距离 ${((bestDistance - 2.46).abs() * 1000).toStringAsFixed(1)}m, '
            '爬升 ${(bestAscent - 308).abs().toStringAsFixed(0)}m');
    } else {
      print('⚠️  未找到符合距离要求（±30m）的配置');
    }
    
    // 输出前5个最佳配置
    print('\n📊 Top 5 最接近的配置:');
    final allResults = <Map<String, dynamic>>[];
    
    for (var speedThreshold in [2.0, 2.5, 3.0, 3.5, 4.0]) {
      for (var coordWindow in [1, 3, 5]) {
        for (var eleWindow in [3, 5, 7, 9, 11]) {
          for (var ascentThreshold in [0.5, 0.8, 1.0, 1.2, 1.5, 2.0]) {
            final filtered = _filterBySpeed(cleanedPoints, speedThreshold);
            final coordSmoothed = GpxService.smoothCoordinates(filtered, coordWindow);
            final eleSmoothed = GpxService.smoothElevation(coordSmoothed, eleWindow);
            
            final dist = _calculateDistance(coordSmoothed);
            final ascent = _calculateAscent(eleSmoothed, ascentThreshold);
            
            final distDiff = (dist - 2.46).abs();
            final ascentDiff = (ascent - 308).abs();
            final totalDiff = distDiff * 200 + ascentDiff;
            
            allResults.add({
              'speed': speedThreshold,
              'coordWin': coordWindow,
              'eleWin': eleWindow,
              'ascentThresh': ascentThreshold,
              'dist': dist,
              'ascent': ascent,
              'diff': totalDiff,
            });
          }
        }
      }
    }
    
    allResults.sort((a, b) => (a['diff'] as double).compareTo(b['diff'] as double));
    
    for (int i = 0; i < 5 && i < allResults.length; i++) {
      final r = allResults[i];
      final dist = r['dist'] as double;
      final ascent = r['ascent'] as double;
      final distError = (dist - 2.46).abs() * 1000;
      final ascentError = (ascent - 308).abs();
      
      print('  ${i + 1}. 速度${r['speed']}m/s, 经纬度${r['coordWin']}, 高度${r['eleWin']}, 阈值${r['ascentThresh']}m '
            '→ ${dist.toStringAsFixed(2)}km, ${ascent.toStringAsFixed(0)}m '
            '(误差: ${distError.toStringAsFixed(0)}m, ${ascentError.toStringAsFixed(0)}m)');
    }
    
    print('========================================\n');
  });
}

// 辅助函数：速度过滤
List<Map<String, dynamic>> _filterBySpeed(List<Map<String, dynamic>> points, double maxSpeed) {
  if (points.length < 2) return points;
  
  const distance = Distance();
  final filtered = <Map<String, dynamic>>[points[0]];
  
  for (int i = 1; i < points.length; i++) {
    final prev = filtered.last;
    final curr = points[i];
    
    final p1 = LatLng(prev['lat'] as double, prev['lon'] as double);
    final p2 = LatLng(curr['lat'] as double, curr['lon'] as double);
    final dist = distance.as(LengthUnit.Meter, p1, p2);
    
    if (prev['time'] != null && curr['time'] != null) {
      final timeInterval = (curr['time'] as DateTime).difference(prev['time'] as DateTime).inSeconds.toDouble();
      
      if (timeInterval > 0) {
        final speed = dist / timeInterval;
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

// 辅助函数：计算距离
double _calculateDistance(List<Map<String, dynamic>> points) {
  if (points.length < 2) return 0.0;
  
  double totalMeters = 0.0;
  const distance = Distance();
  
  for (int i = 0; i < points.length - 1; i++) {
    final p1 = LatLng(points[i]['lat'] as double, points[i]['lon'] as double);
    final p2 = LatLng(points[i + 1]['lat'] as double, points[i + 1]['lon'] as double);
    totalMeters += distance.as(LengthUnit.Meter, p1, p2);
  }
  
  return totalMeters / 1000.0;
}

// 辅助函数：计算爬升
double _calculateAscent(List<Map<String, dynamic>> points, double threshold) {
  if (points.length < 2) return 0.0;
  
  double totalAscent = 0.0;
  
  for (int i = 1; i < points.length; i++) {
    final gain = (points[i]['ele'] as double) - (points[i - 1]['ele'] as double);
    if (gain >= threshold) {
      totalAscent += gain;
    }
  }
  
  return totalAscent;
}

