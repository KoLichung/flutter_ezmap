import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

class DemoVectorMapWidget extends StatelessWidget {
  const DemoVectorMapWidget({
    super.key,
    required this.mapController,
    required this.tileProviders,
    required this.themeWithContours,
    required this.themeWithoutContours,
    required this.showContours,
    required this.onPositionChanged,
    this.sprites,
  });

  final MapController mapController;
  final TileProviders tileProviders;
  final vtr.Theme themeWithContours;
  final vtr.Theme themeWithoutContours;
  final SpriteStyle? sprites;
  final bool showContours;
  final void Function(double zoom, double latitude) onPositionChanged;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: const LatLng(25.04, 121.56),
        initialZoom: 12,
        maxZoom: 18,
        onPositionChanged: (position, hasGesture) {
          onPositionChanged(position.zoom, position.center.latitude);
        },
      ),
      children: [
        VectorTileLayer(
          key: ValueKey('single-layer-${showContours ? 'on' : 'off'}'),
          tileProviders: tileProviders,
          theme: showContours ? themeWithContours : themeWithoutContours,
          sprites: sprites,
          layerMode: VectorTileLayerMode.vector,
          tileOffset: TileOffset.DEFAULT,
        ),
      ],
    );
  }
}
