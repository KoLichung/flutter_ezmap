import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/activity.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import '../services/gps_service.dart';

class RecordingProvider extends ChangeNotifier {
  final GpsService _gpsService = GpsService();

  Activity? _currentActivity;
  bool _isRecording = false;
  bool _isPaused = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _latestCompassHeading;
  
  // 用於通知地圖初始化的回調（包含方向信息）
  Function(LatLng, double?)? onInitialPositionReceived;
  // 用於通知地圖位置更新的回調（包含方向信息）
  Function(LatLng, double?)? onPositionUpdate;
  // 用於通知開始記錄的回調
  Function()? onStartRecording;
  // 用於通知停止記錄的回調
  Function()? onStopRecording;
  
  // Getters
  Activity? get currentActivity => _currentActivity;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  Position? get currentPosition => _currentPosition;

  /// 當前方向（度數 0–360，0 為北）
  /// 優先使用羅盤，若無則使用 GPS heading
  double? get currentHeading =>
      _latestCompassHeading ??
      (_currentPosition != null && _currentPosition!.heading >= 0
          ? _currentPosition!.heading
          : null);

  // 當前統計數據
  double get currentDistance => _currentActivity?.totalDistance ?? 0;
  double get currentAscent => _currentActivity?.totalAscent ?? 0;
  double get currentDescent => _currentActivity?.totalDescent ?? 0;
  double get currentSpeed => _currentPosition?.speed ?? 0;
  double get currentAltitude => _currentPosition?.altitude ?? 0;
  
  // 開始記錄
  Future<void> startRecording() async {
    // 檢查權限
    final hasPermission = await _gpsService.checkPermission();
    if (!hasPermission) {
      // No GPS permission
      return;
    }
    
    _currentActivity = Activity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '記錄 ${DateTime.now().toString().substring(0, 16)}',
      startTime: DateTime.now(),
      trackPoints: [],
    );
    
    _isRecording = true;
    _isPaused = false;
    
    // 通知開始記錄（啟動地圖跟隨模式）
    onStartRecording?.call();

    _startCompassSubscription();

    // 如果還沒有 GPS 監聽，則開始監聽
    _positionSubscription ??= _gpsService.getPositionStream().listen(
      (position) {
        updatePosition(position);
      },
      onError: (error) {
        // GPS error occurred
      },
    );

    notifyListeners();
  }
  
  // 初始化位置（用於啟動時獲取當前位置）
  Future<void> initializePosition() async {
    final position = await _gpsService.getCurrentPosition();
    if (position != null) {
      _currentPosition = position;
      // 通知地圖初始化到這個位置（包含方向信息）
      final heading = position.heading >= 0 ? position.heading : null;
      onInitialPositionReceived?.call(
        LatLng(position.latitude, position.longitude),
        heading,
      );
      notifyListeners();
    }

    _startCompassSubscription();

    // 即使沒有記錄，也要持續監聽位置更新
    _positionSubscription ??= _gpsService.getPositionStream().listen(
      (position) {
        updatePosition(position);
      },
      onError: (error) {
        // GPS error occurred
      },
    );
  }
  
  // 暫停記錄
  void pauseRecording() {
    _isPaused = true;
    notifyListeners();
  }
  
  // 繼續記錄
  void resumeRecording() {
    _isPaused = false;
    notifyListeners();
  }
  
  // 停止記錄並保存
  Future<void> stopRecording() async {
    if (_currentActivity != null) {
      _currentActivity!.endTime = DateTime.now();
      // TODO: 這裡應該保存活動到數據庫
    }
    
    _isRecording = false;
    _isPaused = false;
    
    // 清除當前活動（棕線會消失）
    _currentActivity = null;
    
    // 通知停止記錄（關閉地圖跟隨模式）
    onStopRecording?.call();
    
    // 不停止 GPS 監聽，因為我們需要持續顯示當前位置
    // 只是停止記錄軌跡點
    
    notifyListeners();
  }

  /// 添加紀錄點（需在記錄中且有當前位置）
  void addWaypoint(String text) {
    if (!_isRecording || _currentActivity == null || _currentPosition == null) {
      return;
    }
    final wp = Waypoint(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: text.trim().isEmpty ? '紀錄點' : text.trim(),
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      altitude: _currentPosition!.altitude,
      timestamp: DateTime.now(),
    );
    _currentActivity!.waypoints.add(wp);
    notifyListeners();
  }

  // 捨棄記錄（不保存）
  void discardRecording() {
    _isRecording = false;
    _isPaused = false;
    _currentActivity = null;
    onStopRecording?.call();
    notifyListeners();
  }
  
  @override
  void dispose() {
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }
  
  void _startCompassSubscription() {
    if (_compassSubscription != null) return;
    final stream = FlutterCompass.events;
    if (stream == null) return;
    _compassSubscription = stream.listen(
      (CompassEvent event) {
        if (event.heading != null) {
          _latestCompassHeading = event.heading;
          notifyListeners();
        }
      },
      onError: (_) {},
    );
  }

  // 更新當前位置
  void updatePosition(Position position, {double? compassHeading}) {
    _currentPosition = position;

    // 通知地圖位置更新（傳遞羅盤方向）
    // 優先使用羅盤方向，如果沒有則使用 GPS heading
    final heading =
        compassHeading ?? _latestCompassHeading ?? (position.heading >= 0 ? position.heading : null);
    onPositionUpdate?.call(
      LatLng(position.latitude, position.longitude),
      heading,
    );
    
    if (_isRecording && !_isPaused && _currentActivity != null) {
      _currentActivity!.trackPoints.add(
        TrackPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
          timestamp: DateTime.now(),
          speed: position.speed,
        ),
      );
      
      // 計算距離、爬升、下降
      if (_currentActivity!.trackPoints.length > 1) {
        final points = _currentActivity!.trackPoints;
        final last = points[points.length - 2];
        final current = points.last;

        final distance = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          current.latitude,
          current.longitude,
        );
        _currentActivity!.totalDistance += distance / 1000; // 轉換為公里

        // 爬升/下降（高度差超過 0.5m 才計入）
        final lastAlt = last.altitude ?? 0.0;
        final currAlt = current.altitude ?? 0.0;
        final elevDiff = currAlt - lastAlt;
        if (elevDiff >= 0.5) {
          _currentActivity!.totalAscent += elevDiff;
        } else if (elevDiff <= -0.5) {
          _currentActivity!.totalDescent += elevDiff.abs();
        }
      }
    }
    
    notifyListeners();
  }
}

