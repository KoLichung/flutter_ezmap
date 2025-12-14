import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapProvider extends ChangeNotifier {
  final MapController mapController = MapController();
  
  LatLng _currentCenter = const LatLng(23.5, 121.0); // 台灣中心
  double _currentZoom = 15.0; // 初始放大到15級（適合查看當前位置）
  bool _followLocation = true;
  bool _isInitialized = false; // 標記是否已經初始化定位
  
  // GPX 路線數據
  List<LatLng>? _gpxRoutePoints;
  LatLng? _gpxRouteCenter;
  LatLngBounds? _gpxRouteBounds;
  
  // Getters
  LatLng get currentCenter => _currentCenter;
  double get currentZoom => _currentZoom;
  bool get followLocation => _followLocation;
  bool get isInitialized => _isInitialized;
  List<LatLng>? get gpxRoutePoints => _gpxRoutePoints;
  LatLng? get gpxRouteCenter => _gpxRouteCenter;
  LatLngBounds? get gpxRouteBounds => _gpxRouteBounds;
  
  // 初始化地圖到用戶當前位置
  void initializeToCurrentLocation(LatLng location) {
    if (!_isInitialized) {
      _currentCenter = location;
      _currentZoom = 16.0; // 放大到16級，適合查看周圍環境
      mapController.move(location, _currentZoom);
      _isInitialized = true;
      notifyListeners();
    }
  }
  
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
  
  // 更新缩放级别
  void updateZoom(double zoom) {
    print('[MapProvider] updateZoom called: oldZoom=$_currentZoom, newZoom=$zoom');
    if (_currentZoom != zoom) {
      _currentZoom = zoom;
      print('[MapProvider] Zoom updated, calling notifyListeners()');
      notifyListeners();
    } else {
      print('[MapProvider] Zoom unchanged, skipping notifyListeners()');
    }
  }
  
  // 加載 GPX 路線
  void loadGpxRoute(List<LatLng> points, LatLng center, LatLngBounds bounds) {
    _gpxRoutePoints = points;
    _gpxRouteCenter = center;
    _gpxRouteBounds = bounds;
    
    // 計算適當的縮放級別
    final zoom = _calculateZoomLevel(bounds);
    
    // 移動地圖到路線中心並設置縮放級別
    _currentCenter = center;
    _currentZoom = zoom;
    mapController.move(center, zoom);
    
    notifyListeners();
  }
  
  // 清除 GPX 路線
  void clearGpxRoute() {
    _gpxRoutePoints = null;
    _gpxRouteCenter = null;
    _gpxRouteBounds = null;
    notifyListeners();
  }
  
  // 計算適當的縮放級別
  double _calculateZoomLevel(LatLngBounds bounds) {
    final latDiff = (bounds.north - bounds.south).abs();
    final lonDiff = (bounds.east - bounds.west).abs();
    final maxDiff = latDiff > lonDiff ? latDiff : lonDiff;
    
    // 根據範圍大小計算縮放級別
    if (maxDiff > 10) return 6;
    if (maxDiff > 5) return 7;
    if (maxDiff > 2) return 8;
    if (maxDiff > 1) return 9;
    if (maxDiff > 0.5) return 10;
    if (maxDiff > 0.25) return 11;
    if (maxDiff > 0.1) return 12;
    if (maxDiff > 0.05) return 13;
    if (maxDiff > 0.02) return 14;
    if (maxDiff > 0.01) return 15;
    return 16;
  }
}

