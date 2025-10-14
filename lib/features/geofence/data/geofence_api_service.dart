import 'dart:convert';
import 'package:balumohol/features/authorization/utils/auth_storage.dart';
import 'package:balumohol/features/geofence/models/polygon_feature.dart';
import 'package:balumohol/features/geofence/utils/geo_utils.dart';
import 'package:balumohol/features/geofence/utils/wkb_decoder.dart';
import 'package:http/http.dart' as http;
import 'package:balumohol/core/storage/preferences_service.dart';

// Define GeofenceApiException if not already defined elsewhere
class GeofenceApiException implements Exception {
  final String message;
  final int? statusCode;
  final Uri? uri;
  final String? body;

  GeofenceApiException(this.message, {this.statusCode, this.uri, this.body});

  @override
  String toString() =>
      'GeofenceApiException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}'
      '${uri != null ? ' [uri: $uri]' : ''}'
      '${body != null ? '\nResponse body: $body' : ''}';
}

class GeofenceApiService {
  GeofenceApiService({http.Client? httpClient, Uri? baseUri})
    : _httpClient = httpClient ?? http.Client(),
      _baseUri = baseUri ?? Uri.parse(_defaultBaseUrl);

  static const String _defaultBaseUrl = 'http://192.168.68.133:8080';

  final http.Client _httpClient;
  final Uri _baseUri;

  // Method to get the stored JWT token from preferences
  Future<String?> _getJwtToken() async {
    // Replace 'getToken' with the correct method name or implement it in SharedPreferencesService
    return await AuthStorage.getToken();
  }

  // Fetch Upazila Mouzas
  Future<Map<String, List<String>>> fetchUpazilaMouzas() async {
    final uri = _buildUri(const ['api', 'map', 'upazila']);
    final token = await _getJwtToken();

    final response = await _httpClient.get(
      uri,
      headers: {
        'accept': 'application/json',
        if (token != null)
          'Authorization': 'Bearer $token', // Include JWT in header
      },
    );

    if (response.statusCode != 200) {
      throw GeofenceApiException(
        'Failed to load upazila list (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
        uri: uri,
        body: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    final result = <String, List<String>>{};

    if (decoded is List) {
      for (final entry in decoded) {
        if (entry is Map) {
          for (final upazilaEntry in entry.entries) {
            final key = upazilaEntry.key.toString();
            final value = upazilaEntry.value;
            final mouzas = <String>[];
            if (value is List) {
              for (final item in value) {
                if (item == null) continue;
                final name = item.toString().trim();
                if (name.isEmpty) continue;
                mouzas.add(name);
              }
            }
            mouzas.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            result[key] = mouzas;
          }
        }
      }
    }

    return result;
  }

  // Fetch Mouza Polygons
  Future<List<PolygonFeature>> fetchMouzaPolygons({
    required String upazila,
    required String mouza,
  }) async {
    final segments = ['api', 'map', 'plots', upazila, mouza];
    final uri = _buildUri(segments);
    final token = await _getJwtToken();

    final response = await _httpClient.get(
      uri,
      headers: {
        'accept': 'application/json',
        if (token != null)
          'Authorization': 'Bearer $token', // Include JWT in header
      },
    );

    if (response.statusCode != 200) {
      throw GeofenceApiException(
        'Failed to load mouza "$mouza" for upazila "$upazila" '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
        uri: uri,
        body: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw GeofenceApiException(
        'Unexpected payload for mouza "$mouza": expected JSON array.',
        uri: uri,
        body: response.body,
      );
    }

    final features = <PolygonFeature>[];
    for (int index = 0; index < decoded.length; index++) {
      final item = decoded[index];
      if (item is! Map) continue;

      final rawProps = item['props'];
      final geomHex = item['geom'];
      if (geomHex is! String || geomHex.trim().isEmpty) {
        continue;
      }

      final properties = _normaliseProperties(
        rawProps,
        upazila: upazila,
        mouza: mouza,
      );

      Map<String, dynamic> geometry;
      try {
        geometry = wkbHexToGeoJson(geomHex);
      } catch (error) {
        throw GeofenceApiException(
          'Failed to decode WKB geom for mouza "$mouza" '
          '(index $index): $error',
          uri: uri,
        );
      }

      final featureCollection = {
        'type': 'FeatureCollection',
        'features': [
          {'type': 'Feature', 'geometry': geometry, 'properties': properties},
        ],
      };

      final parsed = parsePolygons(featureCollection);
      for (int partIndex = 0; partIndex < parsed.length; partIndex++) {
        final polygon = parsed[partIndex];
        final identifier = _buildFeatureId(
          properties: properties,
          fallbackIndex: index,
          partIndex: partIndex,
        );
        features.add(
          PolygonFeature(
            id: identifier,
            outer: polygon.outer,
            holes: polygon.holes,
            properties: polygon.properties,
          ),
        );
      }
    }

    return features;
  }

  // Dispose HTTP client
  void dispose() {
    _httpClient.close();
  }

  // Helper function to build URI
  Uri _buildUri(List<String> segments) {
    final baseSegments = _baseUri.pathSegments.where((s) => s.isNotEmpty);
    return _baseUri.replace(pathSegments: [...baseSegments, ...segments]);
  }

  // Helper function to normalize properties
  Map<String, dynamic> _normaliseProperties(
    Object? raw, {
    required String upazila,
    required String mouza,
  }) {
    final props = <String, dynamic>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        props[entry.key.toString()] = entry.value;
      }
    }

    if (!props.containsKey('upazila') || _isEmpty(props['upazila'])) {
      props['upazila'] = upazila;
    }
    if (!props.containsKey('mouza_name') || _isEmpty(props['mouza_name'])) {
      props['mouza_name'] = mouza;
    }
    props['layer_type'] = props['layer_type'] ?? 'mouza';

    if (props.containsKey('plot_numbe') && !props.containsKey('plot_number')) {
      props['plot_number'] = props.remove('plot_numbe');
    }
    if (props.containsKey('plot_no') && !props.containsKey('plot_number')) {
      props['plot_number'] = props.remove('plot_no');
    }
    if (props.containsKey('Shape_Leng') && !props.containsKey('Shape_Length')) {
      props['Shape_Length'] = props.remove('Shape_Leng');
    }

    return props;
  }

  // Helper function to build feature ID
  String _buildFeatureId({
    required Map<String, dynamic> properties,
    required int fallbackIndex,
    required int partIndex,
  }) {
    final plotNumber = properties['plot_number'];
    final objectId = properties['OBJECTID'];
    final base = plotNumber ?? objectId ?? fallbackIndex;
    final mouza = properties['mouza_name'] ?? 'mouza';
    return '${mouza}_$base${partIndex == 0 ? '' : '_$partIndex'}';
  }

  // Helper function to check if a value is empty
  bool _isEmpty(Object? value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    return false;
  }
}
