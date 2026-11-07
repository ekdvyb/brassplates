import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import '../../data/models/enums.dart';

enum DiagramAnchor { left, right, top, bottom, center }

class DiagramStyle {
  const DiagramStyle({
    this.fillColor = '#F4E9D4',
    this.strokeColor = '#8A6A31',
    this.strokeWidth = 2,
    this.fontSize = 14,
    this.textColor = '#2B2620',
    this.opacity = 1,
    this.cornerRadius = 8,
    this.shadow = false,
    this.dashed = false,
  });

  final String fillColor;
  final String strokeColor;
  final double strokeWidth;
  final double fontSize;
  final String textColor;
  final double opacity;
  final double cornerRadius;
  final bool shadow;
  final bool dashed;

  DiagramStyle copyWith({
    String? fillColor,
    String? strokeColor,
    double? strokeWidth,
    double? fontSize,
    String? textColor,
    double? opacity,
    double? cornerRadius,
    bool? shadow,
    bool? dashed,
  }) => DiagramStyle(
    fillColor: fillColor ?? this.fillColor,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    fontSize: fontSize ?? this.fontSize,
    textColor: textColor ?? this.textColor,
    opacity: opacity ?? this.opacity,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    shadow: shadow ?? this.shadow,
    dashed: dashed ?? this.dashed,
  );

  Map<String, dynamic> toJson() => {
    'fill': fillColor,
    'stroke': strokeColor,
    'strokeWidth': strokeWidth,
    'fontSize': fontSize,
    'textColor': textColor,
    'opacity': opacity,
    'cornerRadius': cornerRadius,
    'shadow': shadow,
    'dashed': dashed,
  };

  static DiagramStyle fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DiagramStyle();
    return DiagramStyle(
      fillColor: json['fill'] as String? ?? '#F4E9D4',
      strokeColor: json['stroke'] as String? ?? '#8A6A31',
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14,
      textColor: json['textColor'] as String? ?? '#2B2620',
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 8,
      shadow: json['shadow'] as bool? ?? false,
      dashed: json['dashed'] as bool? ?? false,
    );
  }

  static Color color(String hex, {Color fallback = const Color(0xFF8A6A31)}) {
    final clean = hex.replaceAll('#', '');
    final value = int.tryParse(
      clean.length == 6 ? 'FF$clean' : clean,
      radix: 16,
    );
    return value == null ? fallback : Color(value);
  }
}

class DiagramMetadata {
  const DiagramMetadata({
    this.ip = '',
    this.port = '',
    this.hostname = '',
    this.connectionString = '',
    this.url = '',
  });

  final String ip;
  final String port;
  final String hostname;
  final String connectionString;
  final String url;

  DiagramMetadata copyWith({
    String? ip,
    String? port,
    String? hostname,
    String? connectionString,
    String? url,
  }) => DiagramMetadata(
    ip: ip ?? this.ip,
    port: port ?? this.port,
    hostname: hostname ?? this.hostname,
    connectionString: connectionString ?? this.connectionString,
    url: url ?? this.url,
  );

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'hostname': hostname,
    'connectionString': connectionString,
    'url': url,
  };

  static DiagramMetadata fromJson(Map<String, dynamic>? json) =>
      DiagramMetadata(
        ip: json?['ip'] as String? ?? '',
        port: json?['port'] as String? ?? '',
        hostname: json?['hostname'] as String? ?? '',
        connectionString: json?['connectionString'] as String? ?? '',
        url: json?['url'] as String? ?? '',
      );
}

class DiagramShape {
  DiagramShape({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.label = '',
    this.style = const DiagramStyle(),
    this.metadata = const DiagramMetadata(),
    this.points = const [],
    this.imageData,
    this.rotation = 0,
    this.locked = false,
  });

  String id;
  DiagramShapeType type;
  double x;
  double y;
  double width;
  double height;
  String label;
  DiagramStyle style;
  DiagramMetadata metadata;
  List<Point<double>> points;
  String? imageData;
  double rotation;
  bool locked;

  Rect get rect => Rect.fromLTWH(x, y, width, height);
  Offset get center => Offset(x + width / 2, y + height / 2);

  bool contains(Offset point) {
    if (type == DiagramShapeType.freehand) {
      for (final p in points) {
        if ((Offset(p.x, p.y) - point).distance < 12) return true;
      }
      return false;
    }
    return rect.inflate(4).contains(point);
  }

  Offset anchorPoint(DiagramAnchor anchor) => switch (anchor) {
    DiagramAnchor.left => Offset(x, y + height / 2),
    DiagramAnchor.right => Offset(x + width, y + height / 2),
    DiagramAnchor.top => Offset(x + width / 2, y),
    DiagramAnchor.bottom => Offset(x + width / 2, y + height),
    DiagramAnchor.center => center,
  };

  DiagramShape copyWith({
    String? id,
    DiagramShapeType? type,
    double? x,
    double? y,
    double? width,
    double? height,
    String? label,
    DiagramStyle? style,
    DiagramMetadata? metadata,
    List<Point<double>>? points,
    String? imageData,
    double? rotation,
    bool? locked,
  }) => DiagramShape(
    id: id ?? this.id,
    type: type ?? this.type,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    label: label ?? this.label,
    style: style ?? this.style,
    metadata: metadata ?? this.metadata,
    points: points ?? this.points,
    imageData: imageData ?? this.imageData,
    rotation: rotation ?? this.rotation,
    locked: locked ?? this.locked,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'x': x,
    'y': y,
    'w': width,
    'h': height,
    'label': label,
    'style': style.toJson(),
    'metadata': metadata.toJson(),
    'points': points.map((p) => [p.x, p.y]).toList(),
    if (imageData != null) 'image': imageData,
    'rotation': rotation,
    'locked': locked,
  };

  static DiagramShape fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List?) ?? const [];
    return DiagramShape(
      id: json['id'] as String,
      type: DiagramShapeType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => DiagramShapeType.rectangle,
      ),
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['w'] as num?)?.toDouble() ?? 160,
      height: (json['h'] as num?)?.toDouble() ?? 90,
      label: json['label'] as String? ?? '',
      style: DiagramStyle.fromJson(
        (json['style'] as Map?)?.cast<String, dynamic>(),
      ),
      metadata: DiagramMetadata.fromJson(
        (json['metadata'] as Map?)?.cast<String, dynamic>(),
      ),
      points: rawPoints
          .whereType<List>()
          .map((p) => Point((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
      imageData: json['image'] as String?,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      locked: json['locked'] as bool? ?? false,
    );
  }
}

class DiagramConnector {
  DiagramConnector({
    required this.id,
    required this.fromId,
    required this.toId,
    this.fromAnchor = DiagramAnchor.right,
    this.toAnchor = DiagramAnchor.left,
    this.kind = ConnectorKind.elbow,
    this.label = '',
    this.strokeColor = '#8A6A31',
    this.strokeWidth = 2,
    this.dashed = false,
    this.arrowEnd = true,
    this.arrowStart = false,
  });

  String id;
  String fromId;
  String toId;
  DiagramAnchor fromAnchor;
  DiagramAnchor toAnchor;
  ConnectorKind kind;
  String label;
  String strokeColor;
  double strokeWidth;
  bool dashed;
  bool arrowEnd;
  bool arrowStart;

  DiagramConnector copyWith({
    String? id,
    String? fromId,
    String? toId,
    DiagramAnchor? fromAnchor,
    DiagramAnchor? toAnchor,
    ConnectorKind? kind,
    String? label,
    String? strokeColor,
    double? strokeWidth,
    bool? dashed,
    bool? arrowEnd,
    bool? arrowStart,
  }) => DiagramConnector(
    id: id ?? this.id,
    fromId: fromId ?? this.fromId,
    toId: toId ?? this.toId,
    fromAnchor: fromAnchor ?? this.fromAnchor,
    toAnchor: toAnchor ?? this.toAnchor,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    dashed: dashed ?? this.dashed,
    arrowEnd: arrowEnd ?? this.arrowEnd,
    arrowStart: arrowStart ?? this.arrowStart,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': fromId,
    'to': toId,
    'fromAnchor': fromAnchor.name,
    'toAnchor': toAnchor.name,
    'kind': kind.name,
    'label': label,
    'stroke': strokeColor,
    'strokeWidth': strokeWidth,
    'dashed': dashed,
    'arrowEnd': arrowEnd,
    'arrowStart': arrowStart,
  };

  static DiagramConnector fromJson(Map<String, dynamic> json) =>
      DiagramConnector(
        id: json['id'] as String? ?? '',
        fromId: json['from'] as String? ?? '',
        toId: json['to'] as String? ?? '',
        fromAnchor: DiagramAnchor.values.firstWhere(
          (a) => a.name == json['fromAnchor'],
          orElse: () => DiagramAnchor.right,
        ),
        toAnchor: DiagramAnchor.values.firstWhere(
          (a) => a.name == json['toAnchor'],
          orElse: () => DiagramAnchor.left,
        ),
        kind: ConnectorKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ConnectorKind.elbow,
        ),
        label: json['label'] as String? ?? '',
        strokeColor: json['stroke'] as String? ?? '#8A6A31',
        strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2,
        dashed: json['dashed'] as bool? ?? false,
        arrowEnd: json['arrowEnd'] as bool? ?? true,
        arrowStart: json['arrowStart'] as bool? ?? false,
      );
}

class DiagramViewport {
  const DiagramViewport({this.dx = 80, this.dy = 80, this.scale = 1});
  final double dx;
  final double dy;
  final double scale;

  DiagramViewport copyWith({double? dx, double? dy, double? scale}) =>
      DiagramViewport(
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        scale: scale ?? this.scale,
      );

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy, 'scale': scale};

  static DiagramViewport fromJson(Map<String, dynamic>? json) =>
      DiagramViewport(
        dx: (json?['dx'] as num?)?.toDouble() ?? 80,
        dy: (json?['dy'] as num?)?.toDouble() ?? 80,
        scale: (json?['scale'] as num?)?.toDouble() ?? 1,
      );
}

class DiagramDocument {
  DiagramDocument({
    this.schemaVersion = 1,
    this.title = 'Untitled diagram',
    List<DiagramShape>? shapes,
    List<DiagramConnector>? connectors,
    this.viewport = const DiagramViewport(),
  }) : shapes = shapes ?? [],
       connectors = connectors ?? [];

  final int schemaVersion;
  final String title;
  final List<DiagramShape> shapes;
  final List<DiagramConnector> connectors;
  final DiagramViewport viewport;

  String get searchableText {
    final buffer = StringBuffer(title);
    for (final shape in shapes) {
      buffer.write(
        ' ${shape.label} ${shape.metadata.ip} ${shape.metadata.hostname} ${shape.metadata.port}',
      );
    }
    for (final connector in connectors) {
      buffer.write(' ${connector.label}');
    }
    return buffer.toString().trim();
  }

  DiagramShape? shapeById(String id) {
    for (final shape in shapes) {
      if (shape.id == id) return shape;
    }
    return null;
  }

  DiagramDocument copyWith({
    String? title,
    List<DiagramShape>? shapes,
    List<DiagramConnector>? connectors,
    DiagramViewport? viewport,
  }) => DiagramDocument(
    schemaVersion: schemaVersion,
    title: title ?? this.title,
    shapes: shapes ?? List.of(this.shapes),
    connectors: connectors ?? List.of(this.connectors),
    viewport: viewport ?? this.viewport,
  );

  String toJson() => jsonEncode({
    'schemaVersion': schemaVersion,
    'title': title,
    'shapes': shapes.map((s) => s.toJson()).toList(),
    'connectors': connectors.map((c) => c.toJson()).toList(),
    'viewport': viewport.toJson(),
  });

  static DiagramDocument fromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return DiagramDocument();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return DiagramDocument(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        title: json['title'] as String? ?? 'Untitled diagram',
        shapes: ((json['shapes'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => DiagramShape.fromJson(e.cast<String, dynamic>()))
            .toList(),
        connectors: ((json['connectors'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => DiagramConnector.fromJson(e.cast<String, dynamic>()))
            .toList(),
        viewport: DiagramViewport.fromJson(
          (json['viewport'] as Map?)?.cast<String, dynamic>(),
        ),
      );
    } catch (_) {
      return DiagramDocument();
    }
  }
}
