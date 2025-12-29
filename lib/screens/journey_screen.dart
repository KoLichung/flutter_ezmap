import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../providers/map_provider.dart';
import '../providers/recording_provider.dart';

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  double? _compassHeading;
  
  // 测距相关状态
  bool _isMeasuring = false;
  List<LatLng> _measurementPoints = [];
  final Distance _distance = Distance();

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
        
        // 將羅盤方向傳遞給 RecordingProvider
        // 這樣在更新位置時可以一併更新方向
        final recordingProvider = context.read<RecordingProvider>();
        if (recordingProvider.currentPosition != null) {
          recordingProvider.updatePosition(
            recordingProvider.currentPosition!,
            compassHeading: event.heading,
          );
        }
      }
    });
  }
  
  void _initMapLocation() {
    // 首次打開時定位到當前位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final recordingProvider = context.read<RecordingProvider>();
      final mapProvider = context.read<MapProvider>();
      
      // 設置回調：當初始位置獲取後，初始化地圖（包含方向信息）
      recordingProvider.onInitialPositionReceived = (location, heading) {
        if (!mapProvider.isInitialized) {
          // 使用羅盤數據優先，否則使用 GPS heading
          final currentHeading = _compassHeading ?? heading;
          mapProvider.initializeToCurrentLocation(location, heading: currentHeading);
        }
      };
      
      // 設置回調：當位置更新時，更新地圖位置
      recordingProvider.onPositionUpdate = (location, heading) {
        mapProvider.updateUserLocation(location, heading: heading);
      };
      
      // 設置回調：開始記錄時啟動地圖跟隨模式
      recordingProvider.onStartRecording = () {
        mapProvider.startRecordingMode();
      };
      
      // 設置回調：停止記錄時關閉地圖跟隨模式
      recordingProvider.onStopRecording = () {
        mapProvider.stopRecordingMode();
      };
      
      // 如果已經有位置數據但地圖還沒初始化，立即初始化
      if (recordingProvider.currentPosition != null && !mapProvider.isInitialized) {
        final position = recordingProvider.currentPosition!;
        // 使用羅盤數據優先，否則使用 GPS heading
        final heading = _compassHeading ?? 
            (position.heading != null && position.heading >= 0 ? position.heading : null);
        mapProvider.initializeToCurrentLocation(
          LatLng(position.latitude, position.longitude),
          heading: heading,
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
          
          // 测距按鈕（右侧，与比例尺上缘对齐）- 只在非記錄模式下顯示
          Consumer<RecordingProvider>(
            builder: (context, recordingProvider, child) {
              if (!recordingProvider.isRecording) {
                return Positioned(
                  top: 160,
                  right: 16,
                  child: _buildMeasureButton(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          
          // 輸入座標按鈕（测距按鈕下方）- 只在非記錄模式下顯示
          Consumer<RecordingProvider>(
            builder: (context, recordingProvider, child) {
              if (!recordingProvider.isRecording) {
                return Positioned(
                  top: 220,
                  right: 16,
                  child: _buildCoordinateInputButton(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          
          // 定位按鈕（輸入座標按鈕下方）- 只在非記錄模式下顯示
          Consumer<RecordingProvider>(
            builder: (context, recordingProvider, child) {
              if (!recordingProvider.isRecording) {
                return Positioned(
                  top: 280,
                  right: 16,
                  child: _buildLocationButton(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          
          // 清除路線按鈕（定位按鈕下方）- 只在非記錄模式下顯示
          Consumer2<MapProvider, RecordingProvider>(
            builder: (context, mapProvider, recordingProvider, child) {
              if (!recordingProvider.isRecording &&
                  mapProvider.gpxRoutePoints != null && 
                  mapProvider.gpxRoutePoints!.isNotEmpty) {
                return Positioned(
                  top: 340,
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
          
          // 記錄中的統計信息浮動窗口（覆蓋在地圖上方）
          Consumer<RecordingProvider>(
            builder: (context, recordingProvider, child) {
              if (recordingProvider.isRecording) {
                return Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildStatsOverlay(recordingProvider),
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
            initialRotation: mapProvider.currentRotation,
            minZoom: 5,
            maxZoom: 18,
            interactionOptions: InteractionOptions(
              // 記錄模式下禁用旋轉手勢（因為地圖會自動旋轉）
              flags: mapProvider.isRecordingMode 
                  ? InteractiveFlag.drag | InteractiveFlag.pinchZoom
                  : InteractiveFlag.all,
            ),
            onTap: _isMeasuring ? (tapPosition, point) {
              // 测距模式下，点击地图添加图钉
              setState(() {
                _measurementPoints.add(point);
              });
            } : null,
            onMapEvent: (event) {
              // 检查 zoom 是否变化
              final newZoom = event.camera.zoom;
              final currentZoom = mapProvider.currentZoom;
              
              if ((newZoom - currentZoom).abs() > 0.001) {
                mapProvider.updateZoom(newZoom);
              }
              
              // 更新旋轉角度
              if (event.camera.rotation != mapProvider.currentRotation && !mapProvider.isRecordingMode) {
                mapProvider.updateRotation(event.camera.rotation);
              }
              
              // 如果是用戶手動移動地圖（拖動或手勢操作）
              if (event is MapEventMove || event is MapEventMoveEnd) {
                if (event.source == MapEventSource.dragStart ||
                    event.source == MapEventSource.onDrag ||
                    event.source == MapEventSource.dragEnd) {
                  mapProvider.updateCenter(event.camera.center);
                }
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
            
            // 記錄中的軌跡線（棕色，如果有記錄）
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
                      strokeWidth: 5,
                      color: const Color(0xFF8B4513), // 棕色 (SaddleBrown)
                    ),
                  ],
                );
              },
            ),
            
            // 測距圖釘和連線
            if (_isMeasuring && _measurementPoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _measurementPoints,
                    strokeWidth: 3,
                    color: Colors.green.shade600,
                  ),
                ],
              ),
            
            // 測距圖釘標記
            if (_isMeasuring && _measurementPoints.isNotEmpty)
              MarkerLayer(
                markers: _measurementPoints.asMap().entries.map((entry) {
                  final index = entry.key;
                  final point = entry.value;
                  return Marker(
                    point: point,
                    width: 30,
                    height: 50,
                    alignment: Alignment.topCenter,
                    rotate: true,
                    child: CustomPaint(
                      size: const Size(30, 50),
                      painter: PinMarkerPainter(
                        number: index + 1,
                        color: Colors.green.shade600,
                      ),
                    ),
                  );
                }).toList(),
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
                      alignment: Alignment.center,
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
    if (_isMeasuring) {
      return _buildMeasureControlPanel();
    }
    
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
              // 座標部分（可點擊複製）
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () {
                    if (position != null) {
                      final lat = position.latitude.toStringAsFixed(6);
                      final lng = position.longitude.toStringAsFixed(6);
                      final coordText = '$lat, $lng';
                      
                      Clipboard.setData(ClipboardData(text: coordText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已複製座標: $coordText'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
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
  
  // 测距控制面板
  Widget _buildMeasureControlPanel() {
    final totalDistance = _calculateTotalDistance();
    
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
          // 回复按钮
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _measurementPoints.isNotEmpty ? _undoLastPoint : null,
            color: Colors.blue.shade600,
            iconSize: 24,
          ),
          
          const SizedBox(width: 8),
          
          // 测距结果
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '总距离',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDistance(totalDistance),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 8),
          
          // 清除按钮
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _measurementPoints.isNotEmpty ? _clearAllPoints : null,
            color: Colors.red.shade600,
            iconSize: 24,
          ),
          
          const SizedBox(width: 8),
          
          // 结束测距按钮
          ElevatedButton(
            onPressed: _endMeasuring,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('结束'),
          ),
        ],
      ),
    );
  }

  // 地圖上的位置標記（紅色箭頭指向手機朝向）
  Widget _buildLocationMarker() {
    return Consumer2<RecordingProvider, MapProvider>(
      builder: (context, recordingProvider, mapProvider, child) {
        final position = recordingProvider.currentPosition;
        // 使用羅盤數據，如果沒有則使用 GPS heading
        final heading = _compassHeading ?? (position?.heading != null && position!.heading >= 0 ? position.heading : 0.0);
        
        // 標記旋轉邏輯：
        // - Icons.navigation 默認指向上方
        // - 在記錄模式下：地圖已旋轉 -heading 度，標記需要旋轉 +heading 度來補償
        //   這樣標記在螢幕上的實際方向 = -heading + heading = 0（朝上）
        // - 在正常模式下：標記根據heading旋轉，指向實際方向
        final markerRotation = mapProvider.isRecordingMode 
            ? heading * math.pi / 180  // 記錄模式：補償地圖旋轉，使標記在螢幕上朝上
            : heading * math.pi / 180;  // 正常模式：標記跟隨方向旋轉
        
        return Transform.rotate(
          angle: markerRotation,
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
  
  Widget _buildMeasureButton() {
    return Container(
      decoration: BoxDecoration(
        color: _isMeasuring ? Colors.green.shade600 : Colors.white,
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
        icon: Icon(
          Icons.straighten,
          color: _isMeasuring ? Colors.white : Colors.green.shade600,
        ),
        onPressed: () {
          setState(() {
            if (_isMeasuring) {
              _endMeasuring();
            } else {
              _startMeasuring();
            }
          });
        },
        iconSize: 24,
      ),
    );
  }
  
  Widget _buildCoordinateInputButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        icon: Icon(Icons.edit_location, color: Colors.grey.shade700),
        onPressed: () {
          _showCoordinateInputDialog();
        },
        iconSize: 24,
      ),
    );
  }
  
  Widget _buildLocationButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        icon: Icon(Icons.navigation, color: Colors.grey.shade700),
        onPressed: () {
          final mapProvider = context.read<MapProvider>();
          final recordingProvider = context.read<RecordingProvider>();
          final position = recordingProvider.currentPosition;
          
          if (position != null) {
            // 使用羅盤數據，如果沒有則使用 GPS heading
            final heading = _compassHeading ?? 
                (position.heading != null && position.heading >= 0 ? position.heading : null);
            
            mapProvider.moveToLocation(
              LatLng(position.latitude, position.longitude),
              heading: heading,
            );
          }
        },
        iconSize: 24,
      ),
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
  
  
  void _showCoordinateInputDialog() {
    final coordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('輸入座標'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: coordController,
              decoration: const InputDecoration(
                labelText: '座標',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            Text(
              '請輸入「緯度, 經度」，用逗號分隔\n例如: 24.082746, 120.558229',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final input = coordController.text.trim();
              final parts = input.split(',');
              
              if (parts.length == 2) {
                var lat = double.tryParse(parts[0].trim());
                var lng = double.tryParse(parts[1].trim());
                
                if (lat != null && lng != null && 
                    lat >= -90 && lat <= 90 && 
                    lng >= -180 && lng <= 180) {
                  // 縮減為小數點後 6 位
                  lat = double.parse(lat.toStringAsFixed(6));
                  lng = double.parse(lng.toStringAsFixed(6));
                  
                  Navigator.pop(context);
                  final mapProvider = context.read<MapProvider>();
                  mapProvider.moveToLocation(LatLng(lat, lng));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已移動到座標: $lat, $lng')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('請輸入有效的座標範圍')),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('格式錯誤，請用逗號分隔經緯度')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
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
        final scale = _calculateScaleDistance(zoom, latitude);
        
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
  
  
  // 開始測距
  void _startMeasuring() {
    setState(() {
      _isMeasuring = true;
      _measurementPoints.clear();
    });
  }
  
  // 結束測距
  void _endMeasuring() {
    setState(() {
      _isMeasuring = false;
      _measurementPoints.clear();
    });
  }
  
  // 撤銷上一個圖釘
  void _undoLastPoint() {
    if (_measurementPoints.isNotEmpty) {
      setState(() {
        _measurementPoints.removeLast();
      });
    }
  }
  
  // 清除所有圖釘
  void _clearAllPoints() {
    setState(() {
      _measurementPoints.clear();
    });
  }
  
  // 計算總距離
  double _calculateTotalDistance() {
    if (_measurementPoints.length < 2) {
      return 0.0;
    }
    
    double total = 0.0;
    for (int i = 1; i < _measurementPoints.length; i++) {
      total += _distance.as(
        LengthUnit.Meter,
        _measurementPoints[i - 1],
        _measurementPoints[i],
      );
    }
    return total;
  }
  
  // 格式化距離顯示
  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(2)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
  }
  
  // 記錄中的統計信息浮動窗口
  Widget _buildStatsOverlay(RecordingProvider recordingProvider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Icon(
              Icons.access_time,
              size: 16,
              color: Colors.grey,
            ),
            const SizedBox(width: 4),
            const Text(
              '00:00:00',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 16),
            const Icon(
              Icons.straighten,
              size: 16,
              color: Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              '${recordingProvider.currentDistance.toStringAsFixed(2)} km',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.arrow_upward,
              size: 16,
              color: Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              '${recordingProvider.currentAscent.toStringAsFixed(0)} m',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.arrow_downward,
              size: 16,
              color: Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              '${recordingProvider.currentDescent.toStringAsFixed(0)} m',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 圖釘標記繪製器（圓圈+數字+尖端）
class PinMarkerPainter extends CustomPainter {
  final int number;
  final Color color;

  PinMarkerPainter({
    required this.number,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final circleRadius = 13.0;
    final circleCenter = Offset(centerX, circleRadius + 2);

    // 1. 繪製陰影
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(circleCenter, circleRadius, shadowPaint);

    // 2. 繪製圓圈
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(circleCenter, circleRadius, circlePaint);

    // 3. 繪製白色邊框
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(circleCenter, circleRadius, borderPaint);

    // 4. 繪製下方尖端（三角形）
    final tipPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final tipTop = circleCenter.dy + circleRadius;
    final tipBottom = size.height;
    final tipWidth = 8.0;

    final tipPath = ui.Path()
      ..moveTo(centerX, tipBottom) // 底部尖點
      ..lineTo(centerX - tipWidth / 2, tipTop) // 左上
      ..lineTo(centerX + tipWidth / 2, tipTop) // 右上
      ..close();

    canvas.drawPath(tipPath, tipPaint);

    // 5. 繪製數字
    final textPainter = TextPainter(
      text: TextSpan(
        text: number.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        circleCenter.dx - textPainter.width / 2,
        circleCenter.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant PinMarkerPainter oldDelegate) {
    return oldDelegate.number != number || oldDelegate.color != color;
  }
}

