import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';
import '../providers/recording_provider.dart';

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 地圖顯示
          _buildMap(),
          
          // 座標和高度顯示卡片（左上角）
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: _buildInfoCards(),
          ),
          
          // 指北針和定位按鈕（右側）
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.3,
            child: _buildMapControls(),
          ),
          
          // 暫停按鈕（記錄中顯示）
          Consumer<RecordingProvider>(
            builder: (context, recordingProvider, child) {
              if (recordingProvider.isRecording) {
                return Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildPauseButton(recordingProvider),
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
            
            // 當前位置標記
            Consumer<RecordingProvider>(
              builder: (context, recordingProvider, child) {
                final position = recordingProvider.currentPosition;
                if (position == null) return const SizedBox.shrink();
                
                return MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(position.latitude, position.longitude),
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
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
        
        return Column(
          children: [
            // 座標卡片
            _buildInfoCard(
              title: '座標',
              value: position != null
                  ? '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}'
                  : '-- , --',
            ),
            const SizedBox(height: 8),
            
            // 高度卡片
            _buildInfoCard(
              title: '高度',
              value: position != null
                  ? '${position.altitude.toStringAsFixed(1)} m'
                  : '-- m',
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard({required String title, required String value}) {
    return Container(
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    return Column(
      children: [
        // 指北針按鈕
        _buildCircleButton(
          icon: Icons.explore,
          onPressed: () {
            // TODO: 實現指北針功能
          },
        ),
        const SizedBox(height: 12),
        
        // 定位按鈕
        _buildCircleButton(
          icon: Icons.my_location,
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
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildPauseButton(RecordingProvider recordingProvider) {
    return ElevatedButton(
      onPressed: () {
        if (recordingProvider.isPaused) {
          recordingProvider.resumeRecording();
        } else {
          recordingProvider.pauseRecording();
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: recordingProvider.isPaused ? Colors.green : Colors.orange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(recordingProvider.isPaused ? Icons.play_arrow : Icons.pause),
          const SizedBox(width: 8),
          Text(
            recordingProvider.isPaused ? '繼續' : '暫停',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

