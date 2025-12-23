import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

class MapProvider extends ChangeNotifier {
  final MapController mapController = MapController();
  
  LatLng _currentCenter = const LatLng(23.5, 121.0); // 台灣中心
  double _currentZoom = 17.5; // 初始縮放級別（比例尺約 50-100m）
  double _currentRotation = 0.0; // 地圖旋轉角度（度）
  bool _isInitialized = false; // 標記是否已經初始化定位
  bool _isRecordingMode = false; // 是否處於記錄模式（記錄時地圖會跟隨並旋轉）
  
  // GPX 路線數據
  List<LatLng>? _gpxRoutePoints;
  LatLng? _gpxRouteCenter;
  LatLngBounds? _gpxRouteBounds;
  
  // Getters
  LatLng get currentCenter => _currentCenter;
  double get currentZoom => _currentZoom;
  double get currentRotation => _currentRotation;
  bool get isRecordingMode => _isRecordingMode;
  bool get isInitialized => _isInitialized;
  List<LatLng>? get gpxRoutePoints => _gpxRoutePoints;
  LatLng? get gpxRouteCenter => _gpxRouteCenter;
  LatLngBounds? get gpxRouteBounds => _gpxRouteBounds;
  
  // 初始化地圖到用戶當前位置（只執行一次）
  void initializeToCurrentLocation(LatLng location, {double? heading}) {
    if (!_isInitialized) {
      _currentCenter = location;
      _currentZoom = 17.5; // 放大到17級，比例尺約 50-100m
      
      // 如果有方向數據，旋轉地圖讓標記尖尖朝向螢幕上方
      if (heading != null) {
        _currentRotation = -heading;
        try {
          mapController.rotate(_currentRotation);
        } catch (e) {
          // 忽略錯誤
        }
      }
      
      try {
        mapController.move(location, _currentZoom);
      } catch (e) {
        // MapController 可能還未準備好，稍後會通過定位按鈕更新
      }
      _isInitialized = true;
      notifyListeners();
    }
  }
  
  // 更新用戶位置（只有在記錄模式下才會自動移動地圖）
  void updateUserLocation(LatLng location, {double? heading, Size? screenSize}) {
    // 只有在記錄模式下才自動移動地圖和旋轉
    if (_isRecordingMode) {
      _currentCenter = location;
      
      // 如果有方向數據，更新旋轉角度
      if (heading != null) {
        // 將羅盤方向轉換為地圖旋轉角度（負值，因為地圖旋轉方向相反）
        _currentRotation = -heading;
      }
      
      try {
        mapController.rotate(_currentRotation);
        // 直接將用戶位置設為地圖中心
        mapController.move(location, _currentZoom);
      } catch (e) {
        print('[MapProvider] 錯誤: $e');
      }
      notifyListeners();
    }
    // 正常模式下不移動地圖，標記會自動更新位置（因為它基於 Position）
  }
  
  // 開始記錄模式（地圖會持續跟隨用戶位置並旋轉）
  void startRecordingMode() {
    _isRecordingMode = true;
    // 保持當前旋轉，不重置（保持標記尖尖朝向螢幕上方）
    notifyListeners();
  }
  
  // 停止記錄模式（恢復正常模式）
  void stopRecordingMode() {
    _isRecordingMode = false;
    // 保持當前旋轉，不重置為正北（保持標記尖尖朝向螢幕上方）
    notifyListeners();
  }
  
  // 移動地圖到指定位置（定位按鈕使用）
  void moveToLocation(LatLng location, {double? heading}) {
    _currentCenter = location;
    
    // 如果提供了方向，旋轉地圖讓標記尖尖朝向螢幕上方
    if (heading != null) {
      _currentRotation = -heading;
      try {
        mapController.rotate(_currentRotation);
      } catch (e) {
        print('[MapProvider] 旋轉地圖錯誤: $e');
      }
    }
    
    mapController.move(location, _currentZoom);
    notifyListeners();
  }
  
  // 縮放地圖
  void setZoom(double zoom) {
    _currentZoom = zoom;
    notifyListeners();
  }
  
  // 更新中心點（用戶手動移動地圖時調用）
  void updateCenter(LatLng center) {
    _currentCenter = center;
    // 記錄模式下不允許用戶手動移動地圖，所以這裡不需要退出記錄模式
    notifyListeners();
  }
  
  // 更新旋轉角度
  void updateRotation(double rotation) {
    _currentRotation = rotation;
    notifyListeners();
  }
  
  // 更新缩放级别
  void updateZoom(double zoom) {
    if (_currentZoom != zoom) {
      _currentZoom = zoom;
      notifyListeners();
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

