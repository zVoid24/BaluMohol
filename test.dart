// fetch_api_wkb_to_geojson.dart
//
// Pure Dart (no pubspec, no external packages).
// - Fetches JSON array: [ { "geom": "<EWKB hex>", ... }, ... ]
// - Decodes EWKB/EWKB-hex to GeoJSON geometry
// - Writes GeoJSON FeatureCollection (default) or NDJSON (--ndjson)
//
// Usage:
// dart run test.dart --url http://localhost:8080/api/map/plots/mouza/40_RAHATPUR_1 --out output.geojson
// dart run fetch_api_wkb_to_geojson.dart --url http://localhost:8080/api/map/plots --ndjson --out features.ndjson

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  final cfg = _Args.parse(args);
  if (cfg == null) {
    stderr.writeln('''
Usage:
  dart run fetch_api_wkb_to_geojson.dart --url <API_URL> [--out <file>] [--ndjson]

Examples:
  dart run fetch_api_wkb_to_geojson.dart --url http://localhost:8080/api/map/plots --out output.geojson
  dart run fetch_api_wkb_to_geojson.dart --url http://localhost:8080/api/map/plots --ndjson --out features.ndjson
''');
    exit(64);
  }

  // Fetch using pure dart:io HttpClient
  final body = await _httpGetJson(cfg.url);

  if (body is! List) {
    stderr.writeln('Unexpected response (expected JSON array).');
    exit(1);
  }

  // Decode each row's geom (EWKB hex)
  final features = <Map<String, dynamic>>[];
  var idx = 0;
  for (final row in body) {
    idx++;
    if (row is! Map || !row.containsKey('geom')) continue;
    final hex = (row['geom'] as String).trim();
    try {
      final geom = wkbHexToGeoJson(hex);
      final props = Map<String, dynamic>.from(row)..remove('geom');
      features.add({'type': 'Feature', 'geometry': geom, 'properties': props});
    } catch (e) {
      stderr.writeln('Row $idx: failed to decode EWKB: $e');
    }
  }

  if (cfg.ndjson) {
    // NDJSON: one Feature per line
    final sink = (cfg.outPath != null)
        ? File(cfg.outPath!).openWrite()
        : stdout;
    for (final f in features) {
      sink.writeln(jsonEncode(f));
    }
    if (sink is IOSink) await sink.close();
    stdout.writeln(
      'Wrote ${features.length} features to ${cfg.outPath ?? "(stdout)"} as NDJSON.',
    );
  } else {
    // FeatureCollection
    final fc = {'type': 'FeatureCollection', 'features': features};
    final out = const JsonEncoder.withIndent('  ').convert(fc);
    if (cfg.outPath != null) {
      await File(cfg.outPath!).writeAsString(out);
      stdout.writeln(
        'Wrote ${features.length} features to ${cfg.outPath} as GeoJSON.',
      );
    } else {
      stdout.writeln(out);
    }
  }
}

class _Args {
  final String url;
  final String? outPath;
  final bool ndjson;

  _Args({required this.url, this.outPath, required this.ndjson});

  static _Args? parse(List<String> args) {
    String? url;
    String? outPath;
    bool ndjson = false;

    for (int i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--url' && i + 1 < args.length) {
        url = args[++i];
      } else if (a == '--out' && i + 1 < args.length) {
        outPath = args[++i];
      } else if (a == '--ndjson') {
        ndjson = true;
      }
    }
    if (url == null) return null;
    return _Args(url: url, outPath: outPath, ndjson: ndjson);
  }
}

Future<dynamic> _httpGetJson(String url) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(url);
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final res = await req.close();

    if (res.statusCode != 200) {
      final text = await res.transform(utf8.decoder).join();
      throw HttpException('HTTP ${res.statusCode}: $text', uri: uri);
    }

    final text = await res.transform(utf8.decoder).join();
    return jsonDecode(text);
  } finally {
    client.close(force: true);
  }
}

/// ===================== WKB/EWKB → GeoJSON =====================

Map<String, dynamic> wkbHexToGeoJson(String hex) {
  final bytes = _hexToBytes(hex);
  final rdr = _WkbReader(bytes);
  return rdr.readGeometry();
}

class _WkbReader {
  final ByteData data;
  int o = 0; // offset

  _WkbReader(Uint8List b) : data = ByteData.sublistView(b);

  Map<String, dynamic> readGeometry() {
    final byteOrder = _readUint8(); // 0: BE, 1: LE
    final little = (byteOrder == 1);

    final rawType = _readUint32(little);
    final hasZ = (rawType & 0x80000000) != 0;
    final hasM = (rawType & 0x40000000) != 0;
    final hasSRID = (rawType & 0x20000000) != 0;
    final baseType =
        rawType &
        0x000000FF; // 1=Point,2=LineString,3=Polygon,6=MultiPolygon...

    final dim = 2 + (hasZ ? 1 : 0) + (hasM ? 1 : 0);
    int? srid;
    if (hasSRID) srid = _readUint32(little);

    Map<String, dynamic> geom;
    switch (baseType) {
      case 1:
        geom = _readPoint(little, dim);
        break;
      case 2:
        geom = _readLineString(little, dim);
        break;
      case 3:
        geom = _readPolygon(little, dim);
        break;
      case 6:
        geom = _readMultiPolygon(little, dim);
        break;
      default:
        throw UnsupportedError('Geometry type $baseType not supported.');
    }

    if (srid != null) {
      geom['crs'] = {
        'type': 'name',
        'properties': {'name': 'EPSG:$srid'},
      };
    }
    return geom;
  }

  Map<String, dynamic> _readPoint(bool little, int dim) {
    final coords = _readCoords(little, dim);
    return {'type': 'Point', 'coordinates': _dropMIfPresent(coords)};
  }

  Map<String, dynamic> _readLineString(bool little, int dim) {
    final n = _readUint32(little);
    final line = <List<double>>[];
    for (int i = 0; i < n; i++) {
      line.add(_dropMIfPresent(_readCoords(little, dim)));
    }
    return {'type': 'LineString', 'coordinates': line};
  }

  Map<String, dynamic> _readPolygon(bool little, int dim) {
    final nRings = _readUint32(little);
    final rings = <List<List<double>>>[];
    for (int r = 0; r < nRings; r++) {
      final nPts = _readUint32(little);
      final ring = <List<double>>[];
      for (int i = 0; i < nPts; i++) {
        ring.add(_dropMIfPresent(_readCoords(little, dim)));
      }
      rings.add(ring);
    }
    return {'type': 'Polygon', 'coordinates': rings};
  }

  Map<String, dynamic> _readMultiPolygon(bool little, int dim) {
    final n = _readUint32(little);
    final polys = <List<List<List<double>>>>[];
    for (int i = 0; i < n; i++) {
      // Child geometry header
      final childByteOrder = _readUint8();
      final childLittle = (childByteOrder == 1);
      final childRawType = _readUint32(childLittle);
      final childHasZ = (childRawType & 0x80000000) != 0;
      final childHasM = (childRawType & 0x40000000) != 0;
      final childHasSRID = (childRawType & 0x20000000) != 0;
      final childDim = 2 + (childHasZ ? 1 : 0) + (childHasM ? 1 : 0);
      if (childHasSRID) _readUint32(childLittle); // skip SRID in child

      final nRings = _readUint32(childLittle);
      final rings = <List<List<double>>>[];
      for (int r = 0; r < nRings; r++) {
        final nPts = _readUint32(childLittle);
        final ring = <List<double>>[];
        for (int p = 0; p < nPts; p++) {
          ring.add(_dropMIfPresent(_readCoords(childLittle, childDim)));
        }
        rings.add(ring);
      }
      polys.add(rings);
    }
    return {'type': 'MultiPolygon', 'coordinates': polys};
  }

  List<double> _readCoords(bool little, int dim) {
    final vals = <double>[];
    for (int i = 0; i < dim; i++) {
      vals.add(_readFloat64(little));
    }
    return vals;
  }

  // Drop M if present; keep XYZ if available.
  List<double> _dropMIfPresent(List<double> c) {
    if (c.length == 4) return [c[0], c[1], c[2]]; // XYZM -> XYZ
    return c; // 2D or 3D as-is
  }

  int _readUint8() {
    final v = data.getUint8(o);
    o += 1;
    return v;
  }

  int _readUint32(bool little) {
    final v = little
        ? data.getUint32(o, Endian.little)
        : data.getUint32(o, Endian.big);
    o += 4;
    return v;
  }

  double _readFloat64(bool little) {
    final v = little
        ? data.getFloat64(o, Endian.little)
        : data.getFloat64(o, Endian.big);
    o += 8;
    return v;
  }
}

Uint8List _hexToBytes(String hex) {
  final s = hex.startsWith('0x') ? hex.substring(2) : hex;
  final len = s.length;
  final out = Uint8List(len ~/ 2);
  for (int i = 0; i < len; i += 2) {
    out[i >> 1] = int.parse(s.substring(i, i + 2), radix: 16);
  }
  return out;
}
