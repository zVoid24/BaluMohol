import 'dart:typed_data';

/// Decodes hexadecimal Well-Known Binary (WKB/EWKB) strings into GeoJSON
/// geometry maps.
///
/// Supports Point, LineString, Polygon, and MultiPolygon geometries.
Map<String, dynamic> wkbHexToGeoJson(String hex) {
  final bytes = _hexToBytes(hex);
  final reader = _WkbReader(bytes);
  return reader.readGeometry();
}

Uint8List _hexToBytes(String hex) {
  final source = hex.startsWith('0x') ? hex.substring(2) : hex;
  final length = source.length;
  final output = Uint8List(length ~/ 2);
  for (int i = 0; i < length; i += 2) {
    output[i >> 1] = int.parse(source.substring(i, i + 2), radix: 16);
  }
  return output;
}

class _WkbReader {
  _WkbReader(Uint8List bytes) : data = ByteData.sublistView(bytes);

  final ByteData data;
  int _offset = 0;

  Map<String, dynamic> readGeometry() {
    final byteOrder = _readUint8();
    final littleEndian = byteOrder == 1;

    final rawType = _readUint32(littleEndian);
    final hasZ = (rawType & 0x80000000) != 0;
    final hasM = (rawType & 0x40000000) != 0;
    final hasSrid = (rawType & 0x20000000) != 0;
    final baseType = rawType & 0x000000FF;

    final dimensions = 2 + (hasZ ? 1 : 0) + (hasM ? 1 : 0);
    int? srid;
    if (hasSrid) {
      srid = _readUint32(littleEndian);
    }

    Map<String, dynamic> geometry;
    switch (baseType) {
      case 1:
        geometry = _readPoint(littleEndian, dimensions);
        break;
      case 2:
        geometry = _readLineString(littleEndian, dimensions);
        break;
      case 3:
        geometry = _readPolygon(littleEndian, dimensions);
        break;
      case 6:
        geometry = _readMultiPolygon(littleEndian, dimensions);
        break;
      default:
        throw UnsupportedError('Geometry type $baseType not supported.');
    }

    if (srid != null) {
      geometry = Map<String, dynamic>.from(geometry)
        ..['crs'] = {
          'type': 'name',
          'properties': {'name': 'EPSG:$srid'},
        };
    }

    return geometry;
  }

  Map<String, dynamic> _readPoint(bool littleEndian, int dimensions) {
    final coords = _readCoordinates(littleEndian, dimensions);
    return {
      'type': 'Point',
      'coordinates': _stripMIfPresent(coords),
    };
  }

  Map<String, dynamic> _readLineString(bool littleEndian, int dimensions) {
    final count = _readUint32(littleEndian);
    final coordinates = <List<double>>[];
    for (int i = 0; i < count; i++) {
      coordinates.add(_stripMIfPresent(_readCoordinates(littleEndian, dimensions)));
    }
    return {
      'type': 'LineString',
      'coordinates': coordinates,
    };
  }

  Map<String, dynamic> _readPolygon(bool littleEndian, int dimensions) {
    final ringCount = _readUint32(littleEndian);
    final rings = <List<List<double>>>[];
    for (int ringIndex = 0; ringIndex < ringCount; ringIndex++) {
      final pointCount = _readUint32(littleEndian);
      final ring = <List<double>>[];
      for (int pointIndex = 0; pointIndex < pointCount; pointIndex++) {
        ring.add(_stripMIfPresent(_readCoordinates(littleEndian, dimensions)));
      }
      rings.add(ring);
    }
    return {
      'type': 'Polygon',
      'coordinates': rings,
    };
  }

  Map<String, dynamic> _readMultiPolygon(bool littleEndian, int dimensions) {
    final polygonCount = _readUint32(littleEndian);
    final polygons = <List<List<List<double>>>>[];
    for (int polygonIndex = 0; polygonIndex < polygonCount; polygonIndex++) {
      final childByteOrder = _readUint8();
      final childLittleEndian = childByteOrder == 1;
      final childRawType = _readUint32(childLittleEndian);
      final childHasZ = (childRawType & 0x80000000) != 0;
      final childHasM = (childRawType & 0x40000000) != 0;
      final childHasSrid = (childRawType & 0x20000000) != 0;
      final childDimensions =
          2 + (childHasZ ? 1 : 0) + (childHasM ? 1 : 0);
      if (childHasSrid) {
        _readUint32(childLittleEndian); // discard SRID for children
      }

      final ringCount = _readUint32(childLittleEndian);
      final rings = <List<List<double>>>[];
      for (int ringIndex = 0; ringIndex < ringCount; ringIndex++) {
        final pointCount = _readUint32(childLittleEndian);
        final ring = <List<double>>[];
        for (int pointIndex = 0; pointIndex < pointCount; pointIndex++) {
          ring.add(_stripMIfPresent(
            _readCoordinates(childLittleEndian, childDimensions),
          ));
        }
        rings.add(ring);
      }
      polygons.add(rings);
    }
    return {
      'type': 'MultiPolygon',
      'coordinates': polygons,
    };
  }

  List<double> _readCoordinates(bool littleEndian, int dimensions) {
    final values = <double>[];
    for (int i = 0; i < dimensions; i++) {
      values.add(_readFloat64(littleEndian));
    }
    return values;
  }

  List<double> _stripMIfPresent(List<double> coords) {
    if (coords.length == 4) {
      return [coords[0], coords[1], coords[2]];
    }
    return coords;
  }

  int _readUint8() {
    final value = data.getUint8(_offset);
    _offset += 1;
    return value;
  }

  int _readUint32(bool littleEndian) {
    final value = littleEndian
        ? data.getUint32(_offset, Endian.little)
        : data.getUint32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  double _readFloat64(bool littleEndian) {
    final value = littleEndian
        ? data.getFloat64(_offset, Endian.little)
        : data.getFloat64(_offset, Endian.big);
    _offset += 8;
    return value;
  }
}
