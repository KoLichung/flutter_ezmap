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
          
          // 定位按鈕（信息卡片下方）
          Positioned(
            top: 190, // 調整位置避免重疊
            right: 16,
            child: _buildLocationButton(),
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
              if (event is MapEventMove) {
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
            
            // 軌跡線（如果有記錄）
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

