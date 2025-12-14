import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ezmap/services/gpx_service.dart';
import 'package:gpx/gpx.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final xmlString = await rootBundle.loadString('lib/test_files/合歡東峰.gpx');
  final gpx = GpxReader().fromString(xmlString);
  
  final rawPoints = GpxService.getTrackPointsWithElevation(gpx);
  final cleanedPoints = GpxService.preprocessPoints(rawPoints);
  
  print('测试不同平滑强度:');
  print('strength | 距离(km) | 与2.46km差距');
  print('---------|----------|-------------');
  
  for (var strength in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]) {
    final smoothed = GpxService.smoothCoordinatesWeighted(cleanedPoints, strength);
    final dist = GpxService.calculateTotalDistance(smoothed);
    final diff = ((dist - 2.46).abs() * 1000).toStringAsFixed(0);
    print('  ${strength.toStringAsFixed(1)}    | ${dist.toStringAsFixed(3)}  | ${diff}m');
  }
}
