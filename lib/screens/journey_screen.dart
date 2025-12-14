import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:math' as math;
import '../providers/map_provider.dart';
import '../providers/recording_provider.dart';

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  double? _compassHeading;

  @override
  void initState() {
    super.initState();
    _initCompass();
    _initMapLocation();
  }

  void _initCompass() {
    FlutterCompass.events?.listen((CompassEvent event) {
      if (mounted && event.heading != null) {
        setState(() {
          _compassHeading = event.heading;
        });
      }
    });
  }
  
  void _initMapLocation() {
    // 首次打開時定位到當前位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final recordingProvider = context.read<RecordingProvider>();
      final mapProvider = context.read<MapProvider>();
      
      if (recordingProvider.currentPosition != null && !mapProvider.isInitialized) {
        final position = recordingProvider.currentPosition!;
        mapProvider.initializeToCurrentLocation(
          LatLng(position.latitude, position.longitude),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 地圖顯示
          _buildMap(),
          
          // 座標、高度、方向顯示卡片（上方）
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: _buildInfoCards(),
          ),
          
          // 比例尺（信息卡片下方，左侧）
          Positioned(
            top: 160,
            left: 16,
            child: _buildScaleBar(),
          ),
          
          // 定位按鈕（右侧，与比例尺上缘对齐）
          Positioned(
            top: 160,
            right: 16,
            child: _buildLocationButton(),
          ),
          
          // 導航按鈕（定位按鈕下方）
          Positioned(
            top: 220,
            right: 16,
            child: _buildNavigationButton(),
          ),
          
          // 清除路線按鈕（導航按鈕下方）
          Consumer<MapProvider>(
            builder: (context, mapProvider, child) {
              if (mapProvider.gpxRoutePoints != null && mapProvider.gpxRoutePoints!.isNotEmpty) {
                return Positioned(
                  top: 260,
                  right: 16,
                  child: _buildClearRouteButton(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          
          // 開始記錄按鈕（未記錄時顯示在底部中央）
          Consumer<RecordingProvider>(
            builder: (context, recordingProvider, child) {
              if (!recordingProvider.isRecording) {
                return Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildStartButton(recordingProvider),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Consumer<MapProvider>(
      builder: (context, mapProvider, child) {
        return FlutterMap(
          mapController: mapProvider.mapController,
          options: MapOptions(
            initialCenter: mapProvider.currentCenter,
            initialZoom: mapProvider.currentZoom,
            minZoom: 5,
            maxZoom: 18,
            onMapEvent: (event) {
              print('[JourneyScreen] MapEvent triggered: ${event.runtimeType}');
              print('[JourneyScreen] Camera zoom: ${event.camera.zoom}, center: ${event.camera.center}');
              print('[JourneyScreen] Current provider zoom: ${mapProvider.currentZoom}');
              
              // 检查 zoom 是否变化
              final newZoom = event.camera.zoom;
              final currentZoom = mapProvider.currentZoom;
              
              if ((newZoom - currentZoom).abs() > 0.001) {
                print('[JourneyScreen] Zoom changed from $currentZoom to $newZoom');
                mapProvider.updateZoom(newZoom);
              } else {
                print('[JourneyScreen] Zoom unchanged: $newZoom');
              }
              
              // 更新中心点（移动事件）
              if (event is MapEventMove) {
                print('[JourneyScreen] MapEventMove detected, updating center');
                mapProvider.updateCenter(event.camera.center);
              } else {
                // 对于其他事件，也更新中心点（可能包含缩放）
                mapProvider.updateCenter(event.camera.center);
              }
            },
          ),
          children: [
            // 使用 OpenStreetMap 作為底圖（之後會換成離線地圖）
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.flutter_ezmap',
            ),
            
            // GPX 路線（藍色，如果有加載）
            if (mapProvider.gpxRoutePoints != null && mapProvider.gpxRoutePoints!.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: mapProvider.gpxRoutePoints!,
                    strokeWidth: 4,
                    color: Colors.blue,
                  ),
                ],
              ),
            
            // 記錄中的軌跡線（紅色，如果有記錄）
            Consumer<RecordingProvider>(
              builder: (context, recordingProvider, child) {
                final trackPoints = recordingProvider.currentActivity?.trackPoints ?? [];
                if (trackPoints.isEmpty) return const SizedBox.shrink();
                
                return PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trackPoints
                          .map((p) => LatLng(p.latitude, p.longitude))
                          .toList(),
                      strokeWidth: 4,
                      color: Colors.red,
                    ),
                  ],
                );
              },
            ),
            
            // 當前位置標記（帶羅盤指示）
            Consumer<RecordingProvider>(
              builder: (context, recordingProvider, child) {
                final position = recordingProvider.currentPosition;
                if (position == null) return const SizedBox.shrink();
                
                return MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(position.latitude, position.longitude),
                      width: 50,
                      height: 50,
                      child: _buildLocationMarker(),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCards() {
    return Consumer<RecordingProvider>(
      builder: (context, recordingProvider, child) {
        final position = recordingProvider.currentPosition;
        // 使用羅盤數據，如果沒有則使用 GPS heading
        final heading = _compassHeading ?? (position?.heading != null && position!.heading >= 0 ? position.heading : null);
        
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 座標部分
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '座標',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      position != null
                          ? '${position.latitude.toStringAsFixed(6)}\n${position.longitude.toStringAsFixed(6)}'
                          : '--\n--',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 分隔線
              Container(
                height: 50,
                width: 1,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              
              // 高度部分
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '高度',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      position != null
                          ? '${position.altitude.toStringAsFixed(0)}m'
                          : '--m',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 分隔線
              Container(
                height: 50,
                width: 1,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              
              // 方向部分
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '方向',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      heading != null
                          ? '${heading.toStringAsFixed(0).padLeft(3, '0')}°'
                          : '---°',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 地圖上的位置標記（紅色箭頭指向手機朝向）
  Widget _buildLocationMarker() {
    return Consumer<RecordingProvider>(
      builder: (context, recordingProvider, child) {
        final position = recordingProvider.currentPosition;
        // 使用羅盤數據，如果沒有則使用 GPS heading
        final heading = _compassHeading ?? (position?.heading != null && position!.heading >= 0 ? position.heading : 0.0);
        
        return Transform.rotate(
          angle: (heading * math.pi) / 180,
          child: Icon(
            Icons.navigation,
            color: Colors.red.shade700,
            size: 40,
            shadows: const [
              Shadow(
                color: Colors.white,
                blurRadius: 4,
              ),
              Shadow(
                color: Colors.black,
                blurRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildLocationButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.my_location),
        onPressed: () {
          final mapProvider = context.read<MapProvider>();
          final recordingProvider = context.read<RecordingProvider>();
          final position = recordingProvider.currentPosition;
          
          if (position != null) {
            mapProvider.moveToLocation(
              LatLng(position.latitude, position.longitude),
            );
          }
        },
        color: Colors.white,
        iconSize: 24,
      ),
    );
  }
  
  Widget _buildNavigationButton() {
    return Consumer<MapProvider>(
      builder: (context, mapProvider, child) {
        final hasRoute = mapProvider.gpxRoutePoints != null && mapProvider.gpxRoutePoints!.isNotEmpty;
        
        return Container(
          decoration: BoxDecoration(
            color: hasRoute ? Colors.green.shade600 : Colors.grey.shade400,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.navigation),
            onPressed: () {
              if (hasRoute) {
                _showNavigationDialog();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('導航需匯入路線並在路線附近才可開啟')),
                );
              }
            },
            color: Colors.white,
            iconSize: 24,
          ),
        );
      },
    );
  }
  
  Widget _buildClearRouteButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _showClearRouteDialog(),
        color: Colors.white,
        iconSize: 24,
      ),
    );
  }
  
  void _showNavigationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('開始導航'),
        content: const Text('導航模式會持續追蹤您的位置並計算路線，相對耗電。確定要開始導航嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 實現導航功能
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('開始導航')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
  
  void _showClearRouteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除路線'),
        content: const Text('確定要清除已匯入的路線嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final mapProvider = context.read<MapProvider>();
              mapProvider.clearGpxRoute();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清除路線')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildScaleBar() {
    return Consumer<MapProvider>(
      builder: (context, mapProvider, child) {
        // 根據縮放級別和緯度計算比例尺
        final zoom = mapProvider.currentZoom;
        final latitude = mapProvider.currentCenter.latitude;
        print('[JourneyScreen] _buildScaleBar called with zoom: $zoom, latitude: $latitude');
        final scale = _calculateScaleDistance(zoom, latitude);
        print('[JourneyScreen] Calculated scale: half=${scale['half']}, full=${scale['full']}');
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 刻度線
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 1, height: 6, color: Colors.black),
                  Container(
                    width: 33,
                    height: 2,
                    color: Colors.black,
                  ),
                  Container(width: 1, height: 6, color: Colors.black),
                  Container(
                    width: 33,
                    height: 2,
                    color: Colors.black,
                  ),
                  Container(width: 1, height: 6, color: Colors.black),
                ],
              ),
              const SizedBox(height: 2),
              // 標籤
              SizedBox(
                width: 68,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('0', style: TextStyle(fontSize: 9)),
                    Text(
                      scale['half']!,
                      style: const TextStyle(fontSize: 9),
                    ),
                    Text(
                      scale['full']!,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Map<String, String> _calculateScaleDistance(double zoom, double latitude) {
    print('[JourneyScreen] _calculateScaleDistance called with zoom: $zoom, latitude: $latitude');
    
    // Web Mercator 投影的比例尺計算公式
    // 地球赤道周長約 40075017 米
    // 在 Web Mercator 投影中，每像素的米數 = (40075017 / (256 * 2^zoom)) * cos(latitude)
    // 簡化為：metersPerPixel = 156543.03392 * cos(latitude) / (2^zoom)
    
    // 使用 math.pow 來計算 2^zoom（支持小數 zoom）
    final zoomPower = math.pow(2, zoom);
    
    // 計算緯度的餘弦值（轉換為弧度）
    final latitudeRad = latitude * math.pi / 180;
    final cosLatitude = math.cos(latitudeRad);
    
    // 計算每像素代表的米數
    // 156543.03392 是地球赤道周長 (40075017) / 256
    final metersPerPixel = 156543.03392 * cosLatitude / zoomPower;
    
    // 比例尺顯示100像素寬
    final scalePixels = 100.0;
    final scaleMeters = metersPerPixel * scalePixels;
    
    print('[JourneyScreen] zoomPower: $zoomPower, cosLatitude: $cosLatitude');
    print('[JourneyScreen] metersPerPixel: $metersPerPixel, scaleMeters: $scaleMeters');
    
    // 選擇合適的刻度（50m, 100m, 200m, 500m, 1km, 2km, 5km等）
    final niceScales = [
      50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000
    ];
    
    // 找到最接近但大於 scaleMeters 的刻度
    var selectedScale = niceScales.last;
    for (var scale in niceScales) {
      if (scale >= scaleMeters) {
        selectedScale = scale;
        break;
      }
    }
    
    // 如果 scaleMeters 很小，選擇最小的刻度
    if (scaleMeters < niceScales.first) {
      selectedScale = niceScales.first;
    }
    
    print('[JourneyScreen] selectedScale: $selectedScale');
    
    // 格式化顯示
    String formatDistance(int meters) {
      if (meters >= 1000) {
        return '${meters ~/ 1000}km';
      }
      return '${meters}m';
    }
    
    final result = {
      'half': formatDistance(selectedScale ~/ 2),
      'full': formatDistance(selectedScale),
    };
    
    print('[JourneyScreen] Final scale result: $result');
    
    return result;
  }


  Widget _buildStartButton(RecordingProvider recordingProvider) {
    return ElevatedButton.icon(
      onPressed: () {
        recordingProvider.startRecording();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('開始記錄')),
        );
      },
      icon: const Icon(Icons.play_arrow, size: 28),
      label: const Text(
        '開始記錄',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 8,
        shadowColor: Colors.green.shade900,
      ),
    );
  }
}


