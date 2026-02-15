import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../providers/map_provider.dart';
import '../providers/recording_provider.dart';
import '../providers/mbtiles_tile_provider.dart';
import '../models/map_package.dart';
import '../services/map_tile_service.dart';
import '../resource/mbtiles/mbtiles_local_server.dart';
import '../map/map_engine.dart';
import 'profile_screen.dart';

class JourneyScreen extends StatefulWidget {
  final VoidCallback? onTabActivated; // Tab 激活时的回调

  const JourneyScreen({super.key, this.onTabActivated});

  @override
  JourneyScreenState createState() => JourneyScreenState();
}

class JourneyScreenState extends State<JourneyScreen>
    with WidgetsBindingObserver {
  static const MapEngine _mapEngine = VectorMapEngine();
  static const String _contourSourceId = 'contours_overzoom';
  static const String _vectorMergedMbtilesAssetPath =
      'lib/resource/mbtiles/taiwan-trails-contours-merged-fixed.mbtiles';

  bool get _useVectorOfflineMap => _mapEngine.isVector;

  double? _compassHeading;

  // 测距相关状态
  bool _isMeasuring = false;
  List<LatLng> _measurementPoints = [];
  final Distance _distance = Distance();

  // 输入座标标记状态
  LatLng? _inputCoordinateMarker;

  // 离线地图包
  MapPackage? _currentMapPackage;
  MBTilesTileProvider? _offlineTileProvider;

  // 等高線相關
  bool _showContours = false;
  MBTilesTileProvider? _contourTileProvider;
  MbtilesLocalServer? _vectorServer;
  SpriteStyle? _vectorSprites;
  TileProviders? _vectorTileProviders;
  vtr.Theme? _vectorThemeBaseOnly;
  vtr.Theme? _vectorThemeContoursOnly;
  final MapController _vectorMapController = MapController();
  maplibre.MapLibreMapController? _mapLibreController;
  String? _vectorInitError;
  bool _vectorStyleLoaded = false;
  bool _vectorContoursReady = false;
  bool _vectorReady = false;
  double _vectorCurrentZoom = 12;
  double _vectorCenterLatitude = 25.04;
  maplibre.Line? _vectorGpxLine;
  maplibre.Line? _vectorTrackLine;
  maplibre.Line? _vectorMeasurementLine;
  final List<maplibre.Circle> _vectorMeasurementCircles = [];
  MapProvider? _listenedMapProvider;
  RecordingProvider? _listenedRecordingProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCompass();
    _initMapLocation();
    if (_useVectorOfflineMap) {
      _initVectorOfflineMap();
    } else {
      _loadOfflineMap();
      _loadContourMap(); // 載入等高線
    }

    // 设置 tab 激活回调
    if (widget.onTabActivated != null) {
      widget.onTabActivated!();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep hook for future engine-specific dependency wiring.
  }

  @override
  void didUpdateWidget(JourneyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_useVectorOfflineMap) return;
    // 当 widget 更新时（比如从其他 tab 切换回来），重新加载离线地图包
    debugPrint('[JourneyScreen] Widget 更新，重新加载离线地图包');
    _loadOfflineMap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineTileProvider?.dispose();
    _contourTileProvider?.dispose();
    _vectorServer?.stop();
    super.dispose();
  }

  Future<void> _initVectorOfflineMap() async {
    try {
      if (!await _assetExists(_vectorMergedMbtilesAssetPath)) {
        throw Exception(
          '找不到向量 MBTiles 資源：$_vectorMergedMbtilesAssetPath',
        );
      }
      final server = MbtilesLocalServer(
        mbtilesAssetPath: _vectorMergedMbtilesAssetPath,
        styleAssetPath: 'lib/resource/mbtiles/trails-style.json',
        contourMbtilesAssetPath: '',
      );
      _vectorServer = server;
      await server.start();
      final baseStyle = await StyleReader(
        uri: server.styleUri.toString(),
        logger: const vtr.Logger.console(),
      ).read();
      final themes = await _loadVectorCombinedThemes();

      final providersBySource = Map<String, VectorTileProvider>.from(
        baseStyle.providers.tileProviderBySource,
      );
      if (providersBySource.containsKey(themes.$3)) {
        providersBySource[_contourSourceId] = NetworkVectorTileProvider(
          urlTemplate: server.baseTilesTemplate,
          minimumZoom: 0,
          maximumZoom: 12,
        );
      }

      if (!mounted) return;
      setState(() {
        _vectorSprites = baseStyle.sprites;
        _vectorTileProviders = TileProviders(providersBySource);
        _vectorThemeBaseOnly = themes.$1;
        _vectorThemeContoursOnly = themes.$2;
        _vectorContoursReady = true;
        _vectorReady = true;
        _vectorInitError = null;
      });
      debugPrint(
        '[JourneyScreen] ✅ Vector offline map ready ($_vectorMergedMbtilesAssetPath)',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vectorReady = false;
        _vectorInitError = e.toString();
      });
      debugPrint('[JourneyScreen] ❌ Vector offline map init failed: $e');
    }
  }

  Future<bool> _assetExists(String assetKey) async {
    try {
      final data = await rootBundle.load(assetKey);
      return data.lengthInBytes > 0;
    } catch (_) {
      return false;
    }
  }

  Future<(vtr.Theme, vtr.Theme, String)> _loadVectorCombinedThemes() async {
    final server = _vectorServer;
    if (server == null) {
      throw StateError('Vector server is not initialized.');
    }
    final baseRaw = await rootBundle.loadString(
      'lib/resource/mbtiles/trails-style.json',
    );
    final baseStyleJson = (jsonDecode(baseRaw) as Map).cast<String, dynamic>();

    final baseSources =
        (baseStyleJson['sources'] as Map?)?.cast<String, dynamic>() ?? {};
    final vectorSourceId = baseSources.entries
        .firstWhere(
          (entry) =>
              ((entry.value as Map?)?['type']?.toString() ?? '') == 'vector',
          orElse: () => const MapEntry('openmaptiles', <String, dynamic>{}),
        )
        .key;
    final vectorSource =
        (baseSources[vectorSourceId] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{'type': 'vector'};
    vectorSource.remove('url');
    vectorSource['tiles'] = [server.baseTilesTemplate];
    vectorSource['scheme'] = 'xyz';
    baseSources[vectorSourceId] = vectorSource;

    final contourSource = Map<String, dynamic>.from(vectorSource);
    contourSource['minzoom'] = 0;
    contourSource['maxzoom'] = 12;
    baseSources[_contourSourceId] = contourSource;
    baseStyleJson['sources'] = baseSources;

    baseStyleJson['glyphs'] =
        '${server.baseUri.toString()}/fonts/{fontstack}/{range}.pbf';
    baseStyleJson['sprite'] = '${server.baseUri.toString()}/sprites/sprite';

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

  // 載入等高線地圖
  Future<void> _loadContourMap() async {
    try {
      // 從 assets 複製到應用文檔目錄（只在首次運行時）
      final appDocDir = await getApplicationDocumentsDirectory();
      final mbtiles = File('${appDocDir.path}/taiwan_contours_raster.mbtiles');

      if (!await mbtiles.exists()) {
        debugPrint('[JourneyScreen] 📦 首次運行，正在複製等高線...');
        final data = await rootBundle.load(
          'lib/resource/mbtiles/taiwan_contours_raster.mbtiles',
        );
        await mbtiles.writeAsBytes(data.buffer.asUint8List());
        debugPrint('[JourneyScreen] ✅ 等高線複製完成');
      }

      final contourPackage = MapPackage(
        id: 'contours',
        name: 'Taiwan Contours (Raster)',
        bounds: LatLngBounds(
          const LatLng(21.9, 120.0),
          const LatLng(25.3, 122.0),
        ),
        minZoom: 8,
        maxZoom: 20,
        filePath: mbtiles.path,
        fileSize: await mbtiles.length(),
        downloadedAt: DateTime.now(),
        mapType: MapType.openTrailMap,
      );

      setState(() {
        _contourTileProvider = MBTilesTileProvider(mapPackage: contourPackage);
      });

      debugPrint('[JourneyScreen] ✅ 等高線載入成功！路徑: ${mbtiles.path}');
    } catch (e) {
      debugPrint('[JourneyScreen] ❌ 載入等高線失敗: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当 App 从后台恢复时，重新加载离线地图包
    if (state == AppLifecycleState.resumed) {
      if (_useVectorOfflineMap) return;
      debugPrint('[JourneyScreen] App 恢复，重新加载离线地图包');
      _loadOfflineMap();
    }
  }

  // 公共方法：从外部调用以重新加载地图包
  void reloadOfflineMap() {
    if (_useVectorOfflineMap) return;
    debugPrint('[JourneyScreen] 外部调用重新加载离线地图包');
    _loadOfflineMap();
  }

  // 加载离线地图包
  Future<void> _loadOfflineMap() async {
    try {
      // 從 assets 複製到應用文檔目錄（只在首次運行時）
      final appDocDir = await getApplicationDocumentsDirectory();
      final mbtiles = File('${appDocDir.path}/taiwan_trails_raster.mbtiles');

      if (!await mbtiles.exists()) {
        debugPrint('[JourneyScreen] 📦 首次運行，正在複製底圖...');
        final data = await rootBundle.load(
          'lib/resource/mbtiles/taiwan_trails_raster.mbtiles',
        );
        await mbtiles.writeAsBytes(data.buffer.asUint8List());
        debugPrint('[JourneyScreen] ✅ 底圖複製完成');
      }

      final mapPackage = MapPackage(
        id: 'taiwan_trails_raster',
        name: 'Taiwan Trails (Raster)',
        bounds: LatLngBounds(
          const LatLng(21.9, 120.0),
          const LatLng(25.3, 122.0),
        ),
        minZoom: 8,
        maxZoom: 20,
        filePath: mbtiles.path,
        fileSize: await mbtiles.length(),
        downloadedAt: DateTime.now(),
        mapType: MapType.openTrailMap,
      );

      setState(() {
        _currentMapPackage = mapPackage;
        _offlineTileProvider = MBTilesTileProvider(mapPackage: mapPackage);
      });

      debugPrint('[JourneyScreen] ✅ 底圖載入成功！路徑: ${mbtiles.path}');
    } catch (e) {
      debugPrint('[JourneyScreen] ❌ 載入底圖失敗: $e');
    }
  }

  // 当位置更新时，检查是否需要切换地图包
  Future<void> _checkMapPackage(LatLng location) async {
    if (_useVectorOfflineMap) return;
    if (_currentMapPackage != null &&
        _currentMapPackage!.containsPoint(location)) {
      return; // 当前地图包仍然覆盖该位置
    }

    final mapPackage = await MapTileService.getMapPackageForLocation(location);
    if (mapPackage != null && mounted) {
      setState(() {
        _offlineTileProvider?.dispose();
        _currentMapPackage = mapPackage;
        _offlineTileProvider = MBTilesTileProvider(mapPackage: mapPackage);
      });
    }
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
          mapProvider.initializeToCurrentLocation(
            location,
            heading: currentHeading,
          );
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
      if (recordingProvider.currentPosition != null &&
          !mapProvider.isInitialized) {
        final position = recordingProvider.currentPosition!;
        // 使用羅盤數據優先，否則使用 GPS heading
        final heading = _compassHeading ?? (position.heading >= 0 ? position.heading : null);
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
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.green.shade700,
          statusBarIconBrightness: Brightness.light, // 白色圖標
          statusBarBrightness: Brightness.dark, // iOS 用
        ),
        child: Stack(
          children: [
            // 地圖顯示
            _buildMap(),

            // 綠色頂部狀態欄背景
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: MediaQuery.of(context).padding.top,
                decoration: BoxDecoration(color: Colors.green.shade700),
              ),
            ),

            // 座標、高度、方向顯示卡片（左上角，緊湊布局）
            Positioned(
              top: MediaQuery.of(context).padding.top + 15,
              left: 16,
              child: _buildInfoCards(),
            ),

            // 比例尺（信息卡片下方，左侧）
            Positioned(
              top: MediaQuery.of(context).padding.top + 155,
              left: 16,
              child: _buildScaleBar(),
            ),

            // 右側垂直按鈕列表（由上到下：頭像、搜索、測量、等高線、定位、紀錄）
            Consumer<RecordingProvider>(
              builder: (context, recordingProvider, child) {
                return Positioned(
                  top: MediaQuery.of(context).padding.top + 15,
                  right: 16,
                  child: _buildVerticalActionButtons(recordingProvider),
                );
              },
            ),

            // 清除路線按鈕（定位按鈕下方）- 只在非記錄模式下顯示
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
      ),
    );
  }

  Widget _buildMap() {
    if (_useVectorOfflineMap) {
      if (_vectorInitError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '離線向量地圖初始化失敗：\n$_vectorInitError',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        );
      }
      if (!_vectorReady ||
          _vectorTileProviders == null ||
          _vectorThemeBaseOnly == null ||
          _vectorThemeContoursOnly == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Consumer<MapProvider>(
        builder: (context, mapProvider, child) {
          return FlutterMap(
            mapController: _vectorMapController,
            options: MapOptions(
              initialCenter: const LatLng(25.04, 121.56),
              initialZoom: 12,
              maxZoom: 18,
              minZoom: 8,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: _isMeasuring
                  ? (tapPosition, point) {
                      setState(() {
                        _measurementPoints.add(point);
                      });
                    }
                  : null,
              onPositionChanged: (position, hasGesture) {
                final zoom = position.zoom;
                if ((zoom - _vectorCurrentZoom).abs() < 0.05) return;
                if (!mounted) return;
                setState(() {
                  _vectorCurrentZoom = zoom;
                  _vectorCenterLatitude = position.center.latitude;
                });
              },
            ),
            children: [
              VectorTileLayer(
                tileProviders: _vectorTileProviders!,
                theme: _vectorThemeBaseOnly!,
                sprites: _vectorSprites,
                layerMode: VectorTileLayerMode.vector,
                tileOffset: TileOffset.DEFAULT,
              ),
              if (_showContours)
                VectorTileLayer(
                  tileProviders: _vectorTileProviders!,
                  theme: _vectorThemeContoursOnly!,
                  sprites: _vectorSprites,
                  layerMode: VectorTileLayerMode.vector,
                  tileOffset: TileOffset.DEFAULT,
                ),
              if (mapProvider.gpxRoutePoints != null &&
                  mapProvider.gpxRoutePoints!.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: mapProvider.gpxRoutePoints!,
                      strokeWidth: 4,
                      color: Colors.blue,
                    ),
                  ],
                ),
              Consumer<RecordingProvider>(
                builder: (context, recordingProvider, child) {
                  final trackPoints =
                      recordingProvider.currentActivity?.trackPoints ?? [];
                  if (trackPoints.isEmpty) return const SizedBox.shrink();
                  return PolylineLayer(
                    polylines: [
                      Polyline(
                        points: trackPoints
                            .map((p) => LatLng(p.latitude, p.longitude))
                            .toList(),
                        strokeWidth: 5,
                        color: const Color(0xFF8B4513),
                      ),
                    ],
                  );
                },
              ),
              PolylineLayer(
                polylines: _isMeasuring && _measurementPoints.isNotEmpty
                    ? [
                        Polyline(
                          points: _measurementPoints,
                          strokeWidth: 3,
                          color: Colors.green.shade600,
                        ),
                      ]
                    : List<Polyline>.empty(),
              ),
              ExcludeSemantics(
                child: MarkerLayer(
                  markers: _isMeasuring && _measurementPoints.isNotEmpty
                      ? _measurementPoints.asMap().entries.map((entry) {
                          final index = entry.key;
                          final point = entry.value;
                          return Marker(
                            key: ValueKey('measure-$index'),
                            point: point,
                            width: 30,
                            height: 50,
                            alignment: Alignment.topCenter,
                            rotate: false,
                            child: CustomPaint(
                              size: const Size(30, 50),
                              painter: PinMarkerPainter(
                                number: index + 1,
                                color: Colors.green.shade600,
                              ),
                            ),
                          );
                        }).toList()
                      : [],
                ),
              ),
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
              if (_inputCoordinateMarker != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _inputCoordinateMarker!,
                      width: 30,
                      height: 50,
                      alignment: Alignment.topCenter,
                      rotate: true,
                      child: CustomPaint(
                        size: const Size(30, 50),
                        painter: LocationMarkerPainter(
                          color: Colors.green.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      );
    }

    return Consumer<MapProvider>(
      builder: (context, mapProvider, child) {
        return FlutterMap(
          mapController: mapProvider.mapController,
          options: MapOptions(
            initialCenter: mapProvider.currentCenter,
            initialZoom: mapProvider.currentZoom,
            initialRotation: mapProvider.currentRotation,
            minZoom: 8,
            maxZoom: 20,
            interactionOptions: InteractionOptions(
              flags: mapProvider.isRecordingMode
                  ? InteractiveFlag.drag | InteractiveFlag.pinchZoom
                  : InteractiveFlag.all,
            ),
            onTap: _isMeasuring
                ? (tapPosition, point) {
                    setState(() {
                      _measurementPoints.add(point);
                    });
                  }
                : null,
            onMapEvent: (event) {
              final newZoom = event.camera.zoom;
              final currentZoom = mapProvider.currentZoom;
              if ((newZoom - currentZoom).abs() > 0.001) {
                mapProvider.updateZoom(newZoom);
              }
              if (event.camera.rotation != mapProvider.currentRotation &&
                  !mapProvider.isRecordingMode) {
                mapProvider.updateRotation(event.camera.rotation);
              }
              if (event is MapEventMove || event is MapEventMoveEnd) {
                if (event.source == MapEventSource.dragStart ||
                    event.source == MapEventSource.onDrag ||
                    event.source == MapEventSource.dragEnd) {
                  mapProvider.updateCenter(event.camera.center);
                  _checkMapPackage(event.camera.center);
                }
              }
            },
          ),
          children: [
            if (_offlineTileProvider != null && _currentMapPackage != null)
              TileLayer(tileProvider: _offlineTileProvider!, maxZoom: 20, minZoom: 8),
            if (_showContours && _contourTileProvider != null)
              Opacity(
                opacity: 0.6,
                child: TileLayer(
                  tileProvider: _contourTileProvider!,
                  maxZoom: 20,
                  minZoom: 8,
                ),
              ),
            if (mapProvider.gpxRoutePoints != null &&
                mapProvider.gpxRoutePoints!.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: mapProvider.gpxRoutePoints!,
                    strokeWidth: 4,
                    color: Colors.blue,
                  ),
                ],
              ),
            Consumer<RecordingProvider>(
              builder: (context, recordingProvider, child) {
                final trackPoints =
                    recordingProvider.currentActivity?.trackPoints ?? [];
                if (trackPoints.isEmpty) return const SizedBox.shrink();
                return PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trackPoints
                          .map((p) => LatLng(p.latitude, p.longitude))
                          .toList(),
                      strokeWidth: 5,
                      color: const Color(0xFF8B4513),
                    ),
                  ],
                );
              },
            ),
            PolylineLayer(
              polylines: _isMeasuring && _measurementPoints.isNotEmpty
                  ? [
                      Polyline(
                        points: _measurementPoints,
                        strokeWidth: 3,
                        color: Colors.green.shade600,
                      ),
                    ]
                  : List<Polyline>.empty(),
            ),
            ExcludeSemantics(
              child: MarkerLayer(
                markers: _isMeasuring && _measurementPoints.isNotEmpty
                    ? _measurementPoints.asMap().entries.map((entry) {
                        final index = entry.key;
                        final point = entry.value;
                        return Marker(
                          key: ValueKey('measure-$index'),
                          point: point,
                          width: 30,
                          height: 50,
                          alignment: Alignment.topCenter,
                          rotate: false,
                          child: CustomPaint(
                            size: const Size(30, 50),
                            painter: PinMarkerPainter(
                              number: index + 1,
                              color: Colors.green.shade600,
                            ),
                          ),
                        );
                      }).toList()
                    : [],
              ),
            ),
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
            if (_inputCoordinateMarker != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _inputCoordinateMarker!,
                    width: 30,
                    height: 50,
                    alignment: Alignment.topCenter,
                    rotate: true,
                    child: CustomPaint(
                      size: const Size(30, 50),
                      painter: LocationMarkerPainter(
                        color: Colors.green.shade600,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCards() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Consumer<RecordingProvider>(
      builder: (context, recordingProvider, child) {
        final position = recordingProvider.currentPosition;
        // 使用羅盤數據，如果沒有則使用 GPS heading
        final heading =
            _compassHeading ??
            (position?.heading != null && position!.heading >= 0
                ? position.heading
                : null);

        return InkWell(
          onTap: () {
            if (position != null) {
              final lat = position.latitude.toStringAsFixed(6);
              final lng = position.longitude.toStringAsFixed(6);
              final coordText = '$lat, $lng';

              Clipboard.setData(ClipboardData(text: coordText));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已複製座標: $coordText'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom 級別（第一列）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Zoom ',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    Text(
                      (_useVectorOfflineMap
                              ? _vectorCurrentZoom
                              : context.watch<MapProvider>().currentZoom)
                          .toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 座標
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '座標 ',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    Text(
                      position != null
                          ? position.latitude.toStringAsFixed(6)
                          : '--',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // 經度（縮排對齊）
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Text(
                    position != null
                        ? position.longitude.toStringAsFixed(6)
                        : '--',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const SizedBox(height: 4),
                if (_useVectorOfflineMap) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '等高線 ',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                      Text(
                        _showContours ? 'ON' : 'OFF',
                        style: TextStyle(
                          fontSize: 11,
                          color: _showContours
                              ? Colors.lightGreenAccent
                              : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                // 高度
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '高度 ',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    Text(
                      position != null
                          ? '${position.altitude.toStringAsFixed(0)}m'
                          : '--m',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 方向
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '方向 ',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    Text(
                      heading != null
                          ? '${heading.toStringAsFixed(0)}°'
                          : '--°',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
        if (_isMeasuring) _buildMeasureControlPanel(),
      ],
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
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
        final heading =
            _compassHeading ??
            (position?.heading != null && position!.heading >= 0
                ? position.heading
                : 0.0);

        // 標記旋轉邏輯：
        // - Icons.navigation 默認指向上方
        // - 在記錄模式下：地圖已旋轉 -heading 度，標記需要旋轉 +heading 度來補償
        //   這樣標記在螢幕上的實際方向 = -heading + heading = 0（朝上）
        // - 在正常模式下：標記根據heading旋轉，指向實際方向
        final markerRotation = mapProvider.isRecordingMode
            ? heading *
                  math.pi /
                  180 // 記錄模式：補償地圖旋轉，使標記在螢幕上朝上
            : heading * math.pi / 180; // 正常模式：標記跟隨方向旋轉

        return Transform.rotate(
          angle: markerRotation,
          child: Icon(
            Icons.navigation,
            color: Colors.red.shade700,
            size: 40,
            shadows: const [
              Shadow(color: Colors.white, blurRadius: 4),
              Shadow(color: Colors.black, blurRadius: 2),
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
    final hasMarker = _inputCoordinateMarker != null;

    return Container(
      decoration: BoxDecoration(
        color: hasMarker ? Colors.green.shade600 : Colors.white,
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
          Icons.edit_location,
          color: hasMarker ? Colors.white : Colors.green.shade600,
        ),
        onPressed: () {
          if (hasMarker) {
            // 如果已有标记，删除标记
            setState(() {
              _inputCoordinateMarker = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已清除座標標記'),
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            // 如果没有标记，打开输入对话框
            _showCoordinateInputDialog();
          }
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
        icon: Icon(Icons.navigation, color: Colors.green.shade600),
        onPressed: _moveToCurrentLocation,
        iconSize: 24,
      ),
    );
  }

  // 右側垂直按鈕列表（統一綠色圖標、白色底）
  Widget _buildVerticalActionButtons(RecordingProvider recordingProvider) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 頭像（我的資料）
        _buildActionButton(
          icon: Icons.person,
          onPressed: () {
            // 切換到個人資料頁面
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(onSwitchTab: (index) {}),
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // 2. 搜索
        _buildActionButton(
          icon: Icons.search,
          onPressed: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('搜索功能開發中...')));
          },
        ),
        const SizedBox(height: 12),

        // 3. 測量
        _buildActionButton(
          icon: Icons.straighten,
          onPressed: () {
            setState(() {
              if (_isMeasuring) {
                _endMeasuring();
              } else {
                _startMeasuring();
              }
            });
          },
        ),
        const SizedBox(height: 12),

        // 4. 等高線（使用自定義圖標）
        _buildContourButton(),
        const SizedBox(height: 12),

        // 5. 定位（使用內建圖標）
        _buildActionButton(
          icon: Icons.navigation,
          onPressed: _moveToCurrentLocation,
        ),
        const SizedBox(height: 12),

        // 6. 紀錄（側向三角形）
        _buildRecordButton(recordingProvider),
      ],
    );
  }

  void _moveToCurrentLocation() {
    final recordingProvider = context.read<RecordingProvider>();
    final position = recordingProvider.currentPosition;
    if (position == null) return;

    final heading =
        _compassHeading ?? (position.heading >= 0 ? position.heading : null);
    if (_useVectorOfflineMap) {
      _vectorMapController.move(
        LatLng(position.latitude, position.longitude),
        16,
      );
      return;
    }
    final mapProvider = context.read<MapProvider>();
    mapProvider.moveToLocation(
      LatLng(position.latitude, position.longitude),
      heading: heading,
    );
  }

  Future<void> _setupVectorRuntimeLayers() async {
    final controller = _mapLibreController;
    final server = _vectorServer;
    if (controller == null || server == null || !server.hasContours) return;

    if (_vectorContoursReady) {
      await _setVectorContoursVisible(_showContours);
      return;
    }

    try {
      await controller.addSource(
        'offline-contours-source',
        maplibre.VectorSourceProperties(
          tiles: [server.contourTilesTemplate],
          minzoom: 0,
          maxzoom: 12,
          scheme: 'xyz',
        ),
      );

      await controller.addLineLayer(
        'offline-contours-source',
        'offline-contours-minor',
        const maplibre.LineLayerProperties(
          lineColor: '#B38D6A',
          lineWidth: 0.6,
          lineOpacity: 0.4,
        ),
        sourceLayer: 'contours',
        minzoom: 11,
        filter: ['==', 'type', 'minor'],
      );

      await controller.addLineLayer(
        'offline-contours-source',
        'offline-contours-major',
        const maplibre.LineLayerProperties(
          lineColor: '#8B6F47',
          lineWidth: 1.0,
          lineOpacity: 0.65,
        ),
        sourceLayer: 'contours',
        minzoom: 10,
        filter: ['==', 'type', 'major'],
      );

      await controller.addSymbolLayer(
        'offline-contours-source',
        'offline-contours-label',
        const maplibre.SymbolLayerProperties(
          textField: '{elevation}m',
          textFont: ['Noto Sans Regular'],
          textSize: 10,
          textColor: '#8B6F47',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.5,
          symbolPlacement: 'line',
        ),
        sourceLayer: 'contours',
        minzoom: 12,
        filter: ['==', 'type', 'major'],
      );

      _vectorContoursReady = true;
      await _setVectorContoursVisible(_showContours);
    } catch (e) {
      debugPrint('[JourneyScreen] contour runtime layer setup failed: $e');
    }
  }

  Future<void> _setVectorContoursVisible(bool visible) async {
    if (!_vectorContoursReady) return;
    final controller = _mapLibreController;
    if (controller == null) return;
    for (final layerId in const [
      'offline-contours-minor',
      'offline-contours-major',
      'offline-contours-label',
    ]) {
      await controller.setLayerVisibility(layerId, visible);
    }
  }

  Future<void> _syncVectorRouteOverlays() async {
    final controller = _mapLibreController;
    if (controller == null || !_vectorStyleLoaded) return;

    await _removeVectorLine(_vectorGpxLine);
    _vectorGpxLine = null;
    await _removeVectorLine(_vectorTrackLine);
    _vectorTrackLine = null;

    final gpxPoints = _listenedMapProvider?.gpxRoutePoints;
    if (gpxPoints != null && gpxPoints.length >= 2) {
      _vectorGpxLine = await controller.addLine(
        maplibre.LineOptions(
          geometry: gpxPoints.map(_toMapLibreLatLng).toList(),
          lineColor: '#1E88E5',
          lineWidth: 4,
          lineOpacity: 1,
        ),
      );
    }

    final trackPoints =
        _listenedRecordingProvider?.currentActivity?.trackPoints ?? [];
    if (trackPoints.length >= 2) {
      _vectorTrackLine = await controller.addLine(
        maplibre.LineOptions(
          geometry: trackPoints
              .map((p) => maplibre.LatLng(p.latitude, p.longitude))
              .toList(),
          lineColor: '#8B4513',
          lineWidth: 5,
          lineOpacity: 1,
        ),
      );
    }
  }

  Future<void> _syncVectorMeasurementOverlays() async {
    final controller = _mapLibreController;
    if (controller == null || !_vectorStyleLoaded) return;

    await _removeVectorLine(_vectorMeasurementLine);
    _vectorMeasurementLine = null;
    for (final circle in List<maplibre.Circle>.from(
      _vectorMeasurementCircles,
    )) {
      try {
        await controller.removeCircle(circle);
      } catch (_) {}
    }
    _vectorMeasurementCircles.clear();

    if (!_isMeasuring || _measurementPoints.isEmpty) return;

    for (final point in _measurementPoints) {
      final circle = await controller.addCircle(
        maplibre.CircleOptions(
          geometry: _toMapLibreLatLng(point),
          circleRadius: 5,
          circleColor: '#2E7D32',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
          circleOpacity: 0.95,
        ),
      );
      _vectorMeasurementCircles.add(circle);
    }

    if (_measurementPoints.length >= 2) {
      _vectorMeasurementLine = await controller.addLine(
        maplibre.LineOptions(
          geometry: _measurementPoints.map(_toMapLibreLatLng).toList(),
          lineColor: '#2E7D32',
          lineWidth: 3,
          lineOpacity: 0.9,
        ),
      );
    }
  }

  Future<void> _removeVectorLine(maplibre.Line? line) async {
    final controller = _mapLibreController;
    if (controller == null || line == null) return;
    try {
      await controller.removeLine(line);
    } catch (_) {}
  }

  maplibre.LatLng _toMapLibreLatLng(LatLng point) =>
      maplibre.LatLng(point.latitude, point.longitude);

  // 通用圓形按鈕（統一白底綠色圖標）
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
            color: Colors.black.withOpacity(0.2),
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

  // 定位按鈕（使用地圖上的定位標記，綠色底）

  // 紀錄按鈕（側向三角形）
  Widget _buildRecordButton(RecordingProvider recordingProvider) {
    return GestureDetector(
      onTap: () {
        if (recordingProvider.isRecording) {
          _showStopRecordingDialog(context, recordingProvider);
        } else {
          recordingProvider.startRecording();
          // 記錄開始後顯示底部控制面板
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
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(20, 20),
            painter: recordingProvider.isRecording
                ? _StopIconPainter(color: Colors.red.shade600)
                : _SideTrianglePainter(color: Colors.green.shade600),
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('記錄已保存')));
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

                if (lat != null &&
                    lng != null &&
                    lat >= -90 &&
                    lat <= 90 &&
                    lng >= -180 &&
                    lng <= 180) {
                  // 縮減為小數點後 6 位
                  lat = double.parse(lat.toStringAsFixed(6));
                  lng = double.parse(lng.toStringAsFixed(6));

                  Navigator.pop(context);

                  // 设置标记并移动地图
                  setState(() {
                    _inputCoordinateMarker = LatLng(lat!, lng!);
                  });

                  if (_useVectorOfflineMap) {
                    _vectorMapController.move(LatLng(lat, lng), 16);
                  } else {
                    final mapProvider = context.read<MapProvider>();
                    mapProvider.moveToLocation(LatLng(lat, lng));
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已移動到座標: $lat, $lng'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('請輸入有效的座標範圍')));
                }
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('格式錯誤，請用逗號分隔經緯度')));
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已清除路線')));
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
    if (_useVectorOfflineMap) {
      final scale = _calculateScaleDistance(
        _vectorCurrentZoom,
        _vectorCenterLatitude,
      );
      return _buildScaleBarContent(scale);
    }

    return Consumer<MapProvider>(
      builder: (context, mapProvider, child) {
        // 根據縮放級別和緯度計算比例尺
        final zoom = mapProvider.currentZoom;
        final latitude = mapProvider.currentCenter.latitude;
        final scale = _calculateScaleDistance(zoom, latitude);
        return _buildScaleBarContent(scale);
      },
    );
  }

  Widget _buildScaleBarContent(Map<String, String> scale) {
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

  // 等高線按鈕（圓形背景）
  Widget _buildContourButton() {
    if (_useVectorOfflineMap) {
      final isEnabled = _vectorContoursReady;
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _showContours && isEnabled
              ? Colors.green.shade600
              : Colors.white,
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
          icon: CustomPaint(
            size: const Size(24, 24),
            painter: _ContourIconPainter(
              color: isEnabled
                  ? (_showContours ? Colors.white : Colors.green.shade600)
                  : Colors.grey.shade400,
            ),
          ),
          onPressed: () async {
            if (!isEnabled) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('等高線圖層尚未就緒')));
              return;
            }
            final nextValue = !_showContours;
            setState(() {
              _showContours = nextValue;
            });
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  nextValue ? '✅ 已顯示等高線（向量）' : '已隱藏等高線',
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          padding: EdgeInsets.zero,
        ),
      );
    }

    final isEnabled = _contourTileProvider != null;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _showContours ? Colors.green.shade600 : Colors.white,
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
        icon: CustomPaint(
          size: const Size(24, 24),
          painter: _ContourIconPainter(
            color: isEnabled
                ? (_showContours ? Colors.white : Colors.green.shade600)
                : Colors.grey.shade400,
          ),
        ),
        onPressed: isEnabled
            ? () {
                setState(() {
                  _showContours = !_showContours;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_showContours ? '✅ 已顯示等高線（離線）' : '已隱藏等高線'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('等高線地圖載入中...'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
        padding: EdgeInsets.zero,
      ),
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
      50,
      100,
      200,
      500,
      1000,
      2000,
      5000,
      10000,
      20000,
      50000,
      100000,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('開始記錄')));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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

  // 記錄中的統計信息浮動窗口（含控制按鈕）
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
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 統計信息
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

            // 控制按鈕列
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // 活動分析
                  _buildControlButton(
                    icon: Icons.analytics_outlined,
                    label: '活動分析',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('活動分析功能開發中...')),
                      );
                    },
                  ),

                  // 添加紀錄點
                  _buildControlButton(
                    icon: Icons.add_location_outlined,
                    label: '紀錄點',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('添加紀錄點功能開發中...')),
                      );
                    },
                  ),

                  // 暫停/繼續
                  _buildControlButton(
                    icon: recordingProvider.isPaused
                        ? Icons.play_arrow
                        : Icons.pause,
                    label: recordingProvider.isPaused ? '繼續' : '暫停',
                    color: recordingProvider.isPaused
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    onTap: () {
                      if (recordingProvider.isPaused) {
                        recordingProvider.resumeRecording();
                      } else {
                        recordingProvider.pauseRecording();
                      }
                    },
                  ),

                  // 結束
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

  // 控制按鈕（用於記錄中的底部控制列）
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

// 圖釘標記繪製器（圓圈+數字+尖端）
class PinMarkerPainter extends CustomPainter {
  final int number;
  final Color color;

  PinMarkerPainter({required this.number, required this.color});

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

// 定位標記繪製器（圓圈+定位圖標+尖端）
class LocationMarkerPainter extends CustomPainter {
  final Color color;

  LocationMarkerPainter({required this.color});

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

    // 5. 繪製定位標記（P）
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'P',
        style: TextStyle(
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
  bool shouldRepaint(covariant LocationMarkerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// 側向三角形繪製器（用於紀錄按鈕）
class _SideTrianglePainter extends CustomPainter {
  final Color color;

  _SideTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill;

    final path = ui.Path();
    // 繪製指向右側的三角形（播放按鈕形狀）
    path.moveTo(0, 0); // 左上角
    path.lineTo(size.width, size.height / 2); // 右側中點
    path.lineTo(0, size.height); // 左下角
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SideTrianglePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// 停止圖標繪製器（方塊）
class _StopIconPainter extends CustomPainter {
  final Color color;

  _StopIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill;

    // 繪製圓角方塊
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

// 等高線圖標繪製器（三個橢圓）
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

    // 外層橢圓 (rx=10, ry=8)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(centerX, centerY), width: 20, height: 16),
      paint,
    );

    // 中層橢圓 (rx=7, ry=5)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(centerX, centerY), width: 14, height: 10),
      paint,
    );

    // 內層橢圓 (rx=4, ry=2)
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
