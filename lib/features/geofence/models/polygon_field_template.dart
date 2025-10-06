import 'package:balumohol/features/geofence/models/user_polygon.dart';

class PolygonFieldTemplate {
  const PolygonFieldTemplate({
    required this.id,
    required this.name,
    required this.fields,
  });

  factory PolygonFieldTemplate.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'] as List<dynamic>? ?? const [];
    return PolygonFieldTemplate(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      fields: rawFields
          .whereType<Map<String, dynamic>>()
          .map(PolygonFieldDefinition.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'fields': fields.map((definition) => definition.toJson()).toList(),
    };
  }

  PolygonFieldTemplate copyWith({
    String? id,
    String? name,
    List<PolygonFieldDefinition>? fields,
  }) {
    return PolygonFieldTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      fields: fields ?? this.fields,
    );
  }

  final String id;
  final String name;
  final List<PolygonFieldDefinition> fields;
}

class PolygonFieldDefinition {
  const PolygonFieldDefinition({
    required this.name,
    required this.type,
  });

  factory PolygonFieldDefinition.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String?)?.toLowerCase();
    return PolygonFieldDefinition(
      name: (json['name'] as String? ?? '').trim(),
      type: _fieldTypeFromString(rawType),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
    };
  }

  UserPolygonField toUserPolygonField() {
    return UserPolygonField(name: name, type: type);
  }

  final String name;
  final UserPolygonFieldType type;
}

UserPolygonFieldType _fieldTypeFromString(String? raw) {
  switch (raw) {
    case 'number':
      return UserPolygonFieldType.number;
    case 'date':
      return UserPolygonFieldType.date;
    case 'text':
    default:
      return UserPolygonFieldType.text;
  }
}
