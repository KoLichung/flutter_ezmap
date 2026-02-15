enum MapEngineType { vector, raster }

abstract class MapEngine {
  const MapEngine(this.type);

  final MapEngineType type;

  bool get isVector => type == MapEngineType.vector;
  bool get isRaster => type == MapEngineType.raster;
}

class VectorMapEngine extends MapEngine {
  const VectorMapEngine() : super(MapEngineType.vector);
}

class RasterMapEngine extends MapEngine {
  const RasterMapEngine() : super(MapEngineType.raster);
}
