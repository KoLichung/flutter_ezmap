import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../resource/mbtiles/mbtiles_local_server.dart';

class VectorTilesTestScreen extends StatefulWidget {
  const VectorTilesTestScreen({super.key});

  @override
  State<VectorTilesTestScreen> createState() => _VectorTilesTestScreenState();
}

class _VectorTilesTestScreenState extends State<VectorTilesTestScreen> {
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
  final MapController _mapController = MapController();
  double _currentZoom = _initialZoom;

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  @override
  void dispose() {
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
        // Force contour provider max zoom to 12 so high zoom uses overzoom.
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
    // Force point placement so labels no longer follow line angle.
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
      appBar: AppBar(
        title: const Text('flutter_map + vector_map_tiles'),
        actions: [
          IconButton(
            tooltip: _showContours ? '隱藏等高線圖層' : '顯示等高線圖層',
            onPressed: () {
              setState(() {
                _showContours = !_showContours;
              });
            },
            icon: Icon(_showContours ? Icons.layers_clear : Icons.terrain),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Load style failed:\n$_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (_tileProviders == null ||
        _themeBaseOnly == null ||
        _themeContoursOnly == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(25.04, 121.56),
        initialZoom: _initialZoom,
        maxZoom: 18,
        onPositionChanged: (position, hasGesture) {
          final zoom = position.zoom;
          if ((zoom - _currentZoom).abs() < 0.05) return;
          if (!mounted) return;
          setState(() {
            _currentZoom = zoom;
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
        Positioned(
          top: 12,
          left: 12,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Zoom ${_currentZoom.toStringAsFixed(2)}  •  Contour ${_showContours ? 'ON' : 'OFF'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
