import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../providers/map_provider.dart';
import '../providers/recording_provider.dart';
import '../resource/mbtiles/mbtiles_local_server.dart';
import 'profile_screen.dart';

/// NewJourneyScreen: vector_tiles_test_screen 邏輯 + journey_screen UI 結構
class NewJourneyScreen extends StatefulWidget {
  const NewJourneyScreen({super.key});

  @override
  State<NewJourneyScreen> createState() => _NewJourneyScreenState();
}

class _NewJourneyScreenState extends State<NewJourneyScreen>
    with TickerProviderStateMixin {
  static const String _contourSourceId = 'contours_overzoom';
  static const double _initialZoom = 12;

  final MbtilesLocalServer _server = MbtilesLocalServer(
    mbtilesAssetPath:
        'lib/resource/mbtiles/taiwan-trails-contours-merged-fixed.mbtiles',
    styleAssetPath: 'lib/resource/mbtiles/trails-style.json',
    contourMbtilesAssetPath: '',
  );
  SpriteStyle? _sprites;
  TileProviders? _tileProviders;
  vtr.Theme? _themeBaseOnly;
  vtr.Theme? _themeContoursOnly;
  String? _error;
  bool _showContours = false;
  LatLng? _pendingLocationToCenter;
  late final AnimatedMapController _animatedMapController = AnimatedMapController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    curve: Curves.easeInOut,
    cancelPreviousAnimations: true,
  );
  double _currentZoom = _initialZoom;
  double _centerLatitude = 25.04; // 台灣緯度預設值

  @override
  void initState() {
    super.initState();
    _loadStyle();
    final recordingProvider = context.read<RecordingProvider>();
    recordingProvider.onInitialPositionReceived = (location, heading) {
      if (_tileProviders != null && mounted) {
        _animatedMapController.centerOnPoint(location, zoom: 16);
      } else {
        _pendingLocationToCenter = location;
      }
    };
    final position = recordingProvider.currentPosition;
    if (position != null) {
      _pendingLocationToCenter = LatLng(position.latitude, position.longitude);
    }
  }

  @override
  void dispose() {
    _animatedMapController.dispose();
    _server.stop();
    super.dispose();
  }

  Future<void> _loadStyle() async {
    try {
      await _server.start();
      final baseStyle = await StyleReader(
        uri: _server.styleUri.toString(),
        logger: const vtr.Logger.console(),
      ).read();
      final themes = await _loadCombinedThemes();
      final providersBySource = Map<String, VectorTileProvider>.from(
        baseStyle.providers.tileProviderBySource,
      );
      if (providersBySource.containsKey(themes.$3)) {
        providersBySource[_contourSourceId] = NetworkVectorTileProvider(
          urlTemplate: _server.baseTilesTemplate,
          minimumZoom: 0,
          maximumZoom: 12,
        );
      }
      if (!mounted) return;
      setState(() {
        _sprites = baseStyle.sprites;
        _tileProviders = TileProviders(providersBySource);
        _themeBaseOnly = themes.$1;
        _themeContoursOnly = themes.$2;
      });
      if (_pendingLocationToCenter != null) {
        final loc = _pendingLocationToCenter!;
        _pendingLocationToCenter = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _animatedMapController.centerOnPoint(loc, zoom: 16);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<(vtr.Theme, vtr.Theme, String)> _loadCombinedThemes() async {
    final baseRaw = await rootBundle.loadString(
      'lib/resource/mbtiles/trails-style.json',
    );
    final baseStyleJson = (jsonDecode(baseRaw) as Map).cast<String, dynamic>();

    final baseSources =
        (baseStyleJson['sources'] as Map?)?.cast<String, dynamic>() ?? {};
    final vectorSourceId = baseSources.entries
        .firstWhere(
          (entry) => ((entry.value as Map?)?['type']?.toString() ?? '') == 'vector',
          orElse: () => const MapEntry('openmaptiles', <String, dynamic>{}),
        )
        .key;

    final baseVectorSource =
        (baseSources[vectorSourceId] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{'type': 'vector'};
    final contourSource = Map<String, dynamic>.from(baseVectorSource);
    contourSource['minzoom'] = 0;
    contourSource['maxzoom'] = 12;
    baseSources[_contourSourceId] = contourSource;
    baseStyleJson['sources'] = baseSources;

    final rawBaseLayers =
        (baseStyleJson['layers'] as List?)?.cast<dynamic>() ?? [];
    final baseLayers = rawBaseLayers.map((layer) {
      final layerMap = (layer as Map?)?.cast<String, dynamic>();
      if (layerMap == null) return layer;
      return _forceSymbolUpright(Map<String, dynamic>.from(layerMap));
    }).toList();
    final contourRaw = await rootBundle.loadString(
      'lib/resource/mbtiles/contours-style.json',
    );
    final contourStyleJson =
        (jsonDecode(contourRaw) as Map).cast<String, dynamic>();
    final contourLayers =
        (contourStyleJson['layers'] as List?)?.cast<dynamic>() ?? [];
    final appendedContourLayers = contourLayers
        .where((layer) {
          final layerMap = (layer as Map?)?.cast<String, dynamic>();
          if (layerMap == null || layerMap['type'] == 'background') {
            return false;
          }
          return layerMap['source-layer']?.toString() == 'contours';
        })
        .map((layer) {
          final map = Map<String, dynamic>.from(
            (layer as Map).cast<String, dynamic>(),
          );
          map['source'] = _contourSourceId;
          map['minzoom'] = 0;
          return _forceSymbolUpright(map);
        })
        .toList();

    final baseOnlyJson = Map<String, dynamic>.from(baseStyleJson);
    baseOnlyJson['id'] = 'trails-base';
    baseOnlyJson['layers'] = baseLayers;

    final contoursOnlyJson = <String, dynamic>{
      'version': 8,
      'id': 'trails-contours',
      'sources': baseSources,
      'layers': appendedContourLayers,
    };

    final logger = const vtr.Logger.console();
    final baseOnly = vtr.ThemeReader(logger: logger).read(baseOnlyJson);
    final contoursOnly =
        vtr.ThemeReader(logger: logger).read(contoursOnlyJson);
    return (baseOnly, contoursOnly, vectorSourceId);
  }

  Map<String, dynamic> _forceSymbolUpright(Map<String, dynamic> layer) {
    if (layer['type']?.toString() != 'symbol') return layer;
    final layout = Map<String, dynamic>.from(
      (layer['layout'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    layout['symbol-placement'] = 'point';
    layout['text-rotation-alignment'] = 'viewport';
    layout['icon-rotation-alignment'] = 'viewport';
    layout['text-pitch-alignment'] = 'viewport';
    layout['text-keep-upright'] = true;
    layout['icon-keep-upright'] = true;
    layer['layout'] = layout;
    return layer;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.green.shade700,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Stack(
          children: [
            _buildMap(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: MediaQuery.of(context).padding.top,
                decoration: BoxDecoration(color: Colors.green.shade700),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 15,
              left: 16,
              child: _buildInfoCards(),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 95,
              left: 16,
              child: _buildScaleBar(),
            ),
            Consumer<RecordingProvider>(
              builder: (context, recordingProvider, child) {
                return Positioned(
                  top: MediaQuery.of(context).padding.top + 15,
                  right: 16,
                  child: _buildVerticalActionButtons(recordingProvider),
                );
              },
            ),
            Consumer2<MapProvider, RecordingProvider>(
              builder: (context, mapProvider, recordingProvider, child) {
                if (!recordingProvider.isRecording &&
                    mapProvider.gpxRoutePoints != null &&
                    mapProvider.gpxRoutePoints!.isNotEmpty) {
                  return Positioned(
                    top: MediaQuery.of(context).padding.top + 305,
                    right: 16,
                    child: _buildClearRouteButton(),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
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
      ),
    );
  }

  Widget _buildMap() {
    if (_error != null) {
      return Container(
        color: const Color(0xFFF2EADA),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Load style failed:\n$_error',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (_tileProviders == null ||
        _themeBaseOnly == null ||
        _themeContoursOnly == null) {
      return Container(
        color: const Color(0xFFF2EADA),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return FlutterMap(
      mapController: _animatedMapController.mapController,
      options: MapOptions(
        initialCenter: const LatLng(25.04, 121.56),
        initialZoom: _initialZoom,
        backgroundColor: const Color(0xFFF2EADA),
        maxZoom: 18,
        onPositionChanged: (position, hasGesture) {
          final zoom = position.zoom;
          final lat = position.center.latitude;
          if ((zoom - _currentZoom).abs() < 0.05 &&
              (lat - _centerLatitude).abs() < 0.001) {
            return;
          }
          if (!mounted) {
            return;
          }
          setState(() {
            _currentZoom = zoom;
            _centerLatitude = lat;
          });
        },
      ),
      children: [
        VectorTileLayer(
          tileProviders: _tileProviders!,
          theme: _themeBaseOnly!,
          sprites: _sprites,
          layerMode: VectorTileLayerMode.vector,
          tileOffset: TileOffset.DEFAULT,
        ),
        if (_showContours)
          VectorTileLayer(
            tileProviders: _tileProviders!,
            theme: _themeContoursOnly!,
            sprites: _sprites,
            layerMode: VectorTileLayerMode.vector,
            tileOffset: TileOffset.DEFAULT,
          ),
        Consumer<RecordingProvider>(
          builder: (context, recordingProvider, child) {
            final position = recordingProvider.currentPosition;
            if (position == null) return const SizedBox.shrink();
            final heading = recordingProvider.currentHeading;
            // 0° = 北（地圖上方），順時針為正；Icons.navigation 預設指向上方
            final angleRad = heading != null ? heading * math.pi / 180 : 0.0;
            return MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(position.latitude, position.longitude),
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  child: Transform.rotate(
                    angle: angleRad,
                    child: Icon(
                      Icons.navigation,
                      color: Colors.red.shade700,
                      size: 40,
                      shadows: const [
                        Shadow(color: Colors.white, blurRadius: 4),
                        Shadow(color: Colors.black, blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildInfoCards() {
    return Consumer<RecordingProvider>(
      builder: (context, recordingProvider, child) {
        final position = recordingProvider.currentPosition;
        final heading = recordingProvider.currentHeading;
        final latStr = position != null
            ? position.latitude.toStringAsFixed(5)
            : '-';
        final lngStr = position != null
            ? position.longitude.toStringAsFixed(5)
            : '-';
        final altStr = position != null
            ? position.altitude.toStringAsFixed(0)
            : '-';
        final headingStr =
            heading != null ? heading.toStringAsFixed(1) : '-';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: 'Zoom ${_currentZoom.toStringAsFixed(2)}  等高線 ',
                    ),
                    TextSpan(
                      text: _showContours ? 'on' : 'off',
                      style: TextStyle(
                        color: _showContours
                            ? Colors.green.shade300
                            : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '經緯度 $latStr, $lngStr',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: '$latStr, $lngStr'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已複製經緯度'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Icon(
                      Icons.copy,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '高度 $altStr m, 方向 $headingStr°',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScaleBar() {
    final scale = _calculateScaleDistance(_currentZoom, _centerLatitude);
    return _buildScaleBarContent(scale);
  }

  Widget _buildScaleBarContent(Map<String, String> scale) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 1, height: 6, color: Colors.black),
              Container(width: 33, height: 2, color: Colors.black),
              Container(width: 1, height: 6, color: Colors.black),
              Container(width: 33, height: 2, color: Colors.black),
              Container(width: 1, height: 6, color: Colors.black),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0', style: TextStyle(fontSize: 9)),
                Text(scale['half']!, style: const TextStyle(fontSize: 9)),
                Text(scale['full']!, style: const TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 根據縮放級別與緯度計算比例尺（Web Mercator 投影）
  Map<String, String> _calculateScaleDistance(double zoom, double latitude) {
    final zoomPower = math.pow(2, zoom);
    final latitudeRad = latitude * math.pi / 180;
    final cosLatitude = math.cos(latitudeRad);
    final metersPerPixel = 156543.03392 * cosLatitude / zoomPower;

    const scalePixels = 100.0;
    final scaleMeters = metersPerPixel * scalePixels;

    const niceScales = [
      50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000,
    ];

    var selectedScale = niceScales.last;
    for (final s in niceScales) {
      if (s >= scaleMeters) {
        selectedScale = s;
        break;
      }
    }
    if (scaleMeters < niceScales.first) {
      selectedScale = niceScales.first;
    }

    String formatDistance(int meters) {
      if (meters >= 1000) return '${meters ~/ 1000}km';
      return '${meters}m';
    }

    return {
      'half': formatDistance(selectedScale ~/ 2),
      'full': formatDistance(selectedScale),
    };
  }

  Widget _buildVerticalActionButtons(RecordingProvider recordingProvider) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          icon: Icons.person,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(onSwitchTab: (index) {}),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildActionButton(icon: Icons.search, onPressed: () {}),
        const SizedBox(height: 12),
        _buildActionButton(icon: Icons.straighten, onPressed: () {}),
        const SizedBox(height: 12),
        _buildContourButton(),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.navigation,
          onPressed: _moveToCurrentLocation,
        ),
        const SizedBox(height: 12),
        _buildRecordButton(recordingProvider),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.green.shade600),
        onPressed: onPressed,
        iconSize: 24,
        padding: EdgeInsets.zero,
      ),
    );
  }

  void _moveToCurrentLocation() {
    final recordingProvider = context.read<RecordingProvider>();
    final position = recordingProvider.currentPosition;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未取得 GPS 位置')),
      );
      return;
    }
    _animatedMapController.centerOnPoint(
      LatLng(position.latitude, position.longitude),
      zoom: 16,
    );
  }

  Widget _buildContourButton() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _showContours ? Colors.green.shade600 : Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: CustomPaint(
          size: const Size(24, 24),
          painter: _ContourIconPainter(
            color: _showContours ? Colors.white : Colors.green.shade600,
          ),
        ),
        onPressed: () {
          setState(() {
            _showContours = !_showContours;
          });
        },
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildRecordButton(RecordingProvider recordingProvider) {
    return GestureDetector(
      onTap: () {
        if (recordingProvider.isRecording) {
          _showStopRecordingDialog(context, recordingProvider);
        } else {
          recordingProvider.startRecording();
        }
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: recordingProvider.isRecording
              ? CustomPaint(
                  size: const Size(16, 16),
                  painter: _StopIconPainter(color: Colors.red.shade600),
                )
              : Icon(
                  Icons.play_arrow,
                  color: Colors.green.shade600,
                  size: 28,
                ),
        ),
      ),
    );
  }

  void _showStopRecordingDialog(
    BuildContext context,
    RecordingProvider recordingProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('結束記錄'),
        content: const Text('確定要結束記錄嗎？軌跡將會被保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              recordingProvider.stopRecording();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('記錄已保存')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('結束'),
          ),
        ],
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
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () {},
        color: Colors.white,
        iconSize: 24,
      ),
    );
  }

  Widget _buildStatsOverlay(RecordingProvider recordingProvider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  const Text(
                    '00:00:00',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.straighten, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${recordingProvider.currentDistance.toStringAsFixed(2)} km',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_upward, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${recordingProvider.currentAscent.toStringAsFixed(0)} m',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildControlButton(
                    icon: Icons.analytics_outlined,
                    label: '活動分析',
                    onTap: () {},
                  ),
                  _buildControlButton(
                    icon: Icons.add_location_outlined,
                    label: '紀錄點',
                    onTap: () {},
                  ),
                  _buildControlButton(
                    icon: recordingProvider.isPaused
                        ? Icons.play_arrow
                        : Icons.pause,
                    label: recordingProvider.isPaused ? '繼續' : '暫停',
                    color: recordingProvider.isPaused
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    onTap: () {},
                  ),
                  _buildControlButton(
                    icon: Icons.stop,
                    label: '結束',
                    color: Colors.red.shade700,
                    onTap: () {
                      _showStopRecordingDialog(context, recordingProvider);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final buttonColor = color ?? Colors.grey.shade700;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: buttonColor),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: buttonColor)),
          ],
        ),
      ),
    );
  }
}

class _StopIconPainter extends CustomPainter {
  final Color color;

  _StopIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _StopIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ContourIconPainter extends CustomPainter {
  final Color color;

  _ContourIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(centerX, centerY), width: 20, height: 16),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(centerX, centerY), width: 14, height: 10),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(centerX, centerY), width: 8, height: 4),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ContourIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
