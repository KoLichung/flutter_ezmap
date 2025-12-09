import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapProvider extends ChangeNotifier {
  final MapController mapController = MapController();
  
  LatLng _currentCenter = const LatLng(23.5, 121.0); // 台灣中心
  double _currentZoom = 10.0;
  bool _followLocation = true;
  
  // Getters
  LatLng get currentCenter => _currentCenter;
  double get currentZoom => _currentZoom;
  bool get followLocation => _followLocation;
  
  // 移動地圖到指定位置
  void moveToLocation(LatLng location) {
    _currentCenter = location;
    mapController.move(location, _currentZoom);
    notifyListeners();
  }
  
  // 縮放地圖
  void setZoom(double zoom) {
    _currentZoom = zoom;
    notifyListeners();
  }
  
  // 切換跟隨位置模式
  void toggleFollowLocation() {
    _followLocation = !_followLocation;
    notifyListeners();
  }
  
  // 更新中心點
  void updateCenter(LatLng center) {
    _currentCenter = center;
    notifyListeners();
  }
}

