import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import 'diagram_model.dart';

IconData iconForShape(DiagramShapeType type) => switch (type) {
  DiagramShapeType.server => Icons.dns_outlined,
  DiagramShapeType.database => Icons.storage_outlined,
  DiagramShapeType.sqlServer => Icons.storage_rounded,
  DiagramShapeType.firewall => Icons.security_outlined,
  DiagramShapeType.cloud => Icons.cloud_outlined,
  DiagramShapeType.router => Icons.router_outlined,
  DiagramShapeType.networkSwitch => Icons.hub_outlined,
  DiagramShapeType.loadBalancer => Icons.alt_route,
  DiagramShapeType.user => Icons.person_outline,
  DiagramShapeType.laptop => Icons.laptop_mac_outlined,
  DiagramShapeType.phone => Icons.phone_iphone_outlined,
  DiagramShapeType.nextcloud => Icons.cloud_queue_outlined,
  DiagramShapeType.storage => Icons.save_outlined,
  DiagramShapeType.terminator => Icons.stop_circle_outlined,
  DiagramShapeType.process => Icons.settings_outlined,
  DiagramShapeType.document => Icons.description_outlined,
  DiagramShapeType.inputOutput => Icons.login_outlined,
  DiagramShapeType.subprocess => Icons.call_split_outlined,
  DiagramShapeType.note => Icons.sticky_note_2_outlined,
  DiagramShapeType.sticky => Icons.sticky_note_2_outlined,
  DiagramShapeType.image => Icons.image_outlined,
  _ => Icons.crop_square,
};

class DiagramPainter extends CustomPainter {
  DiagramPainter({
    required this.document,
    this.viewport,
    this.selectedShapeId,
    this.selectedConnectorId,
    this.showGrid = true,
    this.dark = false,
    this.exporting = false,
  });

  final DiagramDocument document;
  final DiagramViewport? viewport;
  final String? selectedShapeId;
  final String? selectedConnectorId;
  final bool showGrid;
  final bool dark;
  final bool exporting;

  DiagramViewport get _viewport => viewport ?? document.viewport;

  @override
  void paint(Canvas canvas, Size size) {
    if (!exporting) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = dark ? const Color(0xFF161412) : const Color(0xFFFAF7F0),
      );
      if (showGrid) _paintGrid(canvas, size);
    }

    canvas.save();
    canvas.translate(_viewport.dx, _viewport.dy);
    canvas.scale(_viewport.scale);

    for (final connector in document.connectors) {
      _paintConnector(canvas, connector);
    }
    for (final shape in document.shapes) {
      _paintShape(canvas, shape);
    }

    final selectedShape = selectedShapeId == null
        ? null
        : document.shapeById(selectedShapeId!);
    if (selectedShape != null && !exporting) {
      _paintSelection(canvas, selectedShape);
    }

    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.05)
      ..strokeWidth = 1;
    final spacing = 28 * _viewport.scale;
    if (spacing < 6) return;
    final startX = _viewport.dx % spacing;
    final startY = _viewport.dy % spacing;
    for (var x = startX; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = startY; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintShape(Canvas canvas, DiagramShape shape) {
    final style = shape.style;
    final fill = DiagramStyle.color(style.fillColor)
        .withValues(alpha: style.opacity);
    final stroke = DiagramStyle.color(style.strokeColor);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = stroke
      ..strokeWidth = style.strokeWidth;

    final rect = shape.rect;
    if (style.shadow) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(const Offset(3, 3)),
          Radius.circular(style.cornerRadius),
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    switch (shape.type) {
      case DiagramShapeType.ellipse:
      case DiagramShapeType.user:
        canvas.drawOval(rect, fillPaint);
        _strokePath(canvas, Path()..addOval(rect), strokePaint, style.dashed);
        _paintLabel(canvas, shape, rect.deflate(6), bold: false);
        break;
      case DiagramShapeType.diamond:
        final path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, fillPaint);
        _strokePath(canvas, path, strokePaint, style.dashed);
        _paintLabel(canvas, shape, rect.deflate(12), bold: false);
        break;
      case DiagramShapeType.text:
        _paintLabel(canvas, shape, rect, bold: false, force: true);
        break;
      case DiagramShapeType.sticky:
      case DiagramShapeType.note:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()
            ..color = DiagramStyle.color(
              style.fillColor,
              fallback: const Color(0xFFFFE9A8),
            ),
        );
        _paintLabel(canvas, shape, rect.deflate(8), bold: false);
        break;
      case DiagramShapeType.terminator:
        final rrect = RRect.fromRectAndRadius(
          rect,
          Radius.circular(rect.height / 2),
        );
        canvas.drawRRect(rrect, fillPaint);
        _strokePath(canvas, Path()..addRRect(rrect), strokePaint, style.dashed);
        _paintLabel(canvas, shape, rect.deflate(10), bold: false);
        break;
      case DiagramShapeType.document:
        final path = Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.right, rect.bottom - 10)
          ..quadraticBezierTo(
            rect.center.dx,
            rect.bottom + 8,
            rect.left,
            rect.bottom - 10,
          )
          ..close();
        canvas.drawPath(path, fillPaint);
        _strokePath(canvas, path, strokePaint, style.dashed);
        _paintLabel(canvas, shape, rect.deflate(10), bold: false);
        break;
      case DiagramShapeType.subprocess:
        final rrect = RRect.fromRectAndRadius(
          rect,
          Radius.circular(style.cornerRadius),
        );
        canvas.drawRRect(rrect, fillPaint);
        _strokePath(canvas, Path()..addRRect(rrect), strokePaint, style.dashed);
        final inset = style.strokeWidth * 3 + 4;
        canvas.drawLine(
          Offset(rect.left + inset, rect.top),
          Offset(rect.left + inset, rect.bottom),
          strokePaint,
        );
        canvas.drawLine(
          Offset(rect.right - inset, rect.top),
          Offset(rect.right - inset, rect.bottom),
          strokePaint,
        );
        _paintLabel(canvas, shape, rect.deflate(inset + 4), bold: false);
        break;
      case DiagramShapeType.arrow:
      case DiagramShapeType.line:
      case DiagramShapeType.freehand:
        final points = shape.points;
        if (points.isEmpty) break;
        final path = Path()..moveTo(points.first.x, points.first.y);
        for (var i = 1; i < points.length; i++) {
          path.lineTo(points[i].x, points[i].y);
        }
        _strokePath(canvas, path, strokePaint, style.dashed);
        if (shape.type == DiagramShapeType.arrow && points.length > 1) {
          _arrowHead(
            canvas,
            Offset(points[points.length - 2].x, points[points.length - 2].y),
            Offset(points.last.x, points.last.y),
            stroke,
            style.strokeWidth,
          );
        }
        break;
      case DiagramShapeType.process:
      case DiagramShapeType.inputOutput:
      case DiagramShapeType.image:
      case DiagramShapeType.rectangle:
      default:
        final rrect = RRect.fromRectAndRadius(
          rect,
          Radius.circular(style.cornerRadius),
        );
        canvas.drawRRect(rrect, fillPaint);
        _strokePath(canvas, Path()..addRRect(rrect), strokePaint, style.dashed);
        if (_isIconShape(shape.type)) {
          _paintIconShape(canvas, shape, rect, stroke);
        } else {
          _paintLabel(canvas, shape, rect.deflate(10), bold: false);
        }
        break;
    }
  }

  bool _isIconShape(DiagramShapeType type) => switch (type) {
    DiagramShapeType.rectangle ||
    DiagramShapeType.process ||
    DiagramShapeType.inputOutput ||
    DiagramShapeType.image ||
    DiagramShapeType.text ||
    DiagramShapeType.sticky ||
    DiagramShapeType.note ||
    DiagramShapeType.document ||
    DiagramShapeType.subprocess ||
    DiagramShapeType.terminator ||
    DiagramShapeType.arrow ||
    DiagramShapeType.line ||
    DiagramShapeType.freehand ||
    DiagramShapeType.ellipse ||
    DiagramShapeType.diamond ||
    DiagramShapeType.user => false,
    _ => true,
  };

  void _paintIconShape(
    Canvas canvas,
    DiagramShape shape,
    Rect rect,
    Color stroke,
  ) {
    final icon = iconForShape(shape.type);
    final iconSize = math.min(rect.width, rect.height) * 0.32;
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: iconSize,
          color: stroke,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final top = rect.top + rect.height * 0.2;
    iconPainter.paint(
      canvas,
      Offset(rect.center.dx - iconPainter.width / 2, top),
    );
    if (shape.label.trim().isNotEmpty) {
      final labelRect = Rect.fromLTRB(
        rect.left + 4,
        top + iconPainter.height + 2,
        rect.right - 4,
        rect.bottom - 2,
      );
      _paintLabel(canvas, shape, labelRect, bold: false, compact: true);
    }
  }

  void _paintLabel(
    Canvas canvas,
    DiagramShape shape,
    Rect rect, {
    required bool bold,
    bool force = false,
    bool compact = false,
  }) {
    if (shape.label.trim().isEmpty && !force) return;
    final style = shape.style;
    final painter = TextPainter(
      text: TextSpan(
        text: shape.label,
        style: TextStyle(
          color: DiagramStyle.color(
            style.textColor,
            fallback: const Color(0xFF2B2620),
          ),
          fontSize: compact
              ? math.max(9, style.fontSize * 0.8)
              : style.fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          height: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: compact ? 2 : 6,
      ellipsis: '…',
    );
    painter.layout(maxWidth: math.max(20, rect.width));
    final dx = rect.left + (rect.width - painter.width) / 2;
    final dy = rect.top + (rect.height - painter.height) / 2;
    painter.paint(canvas, Offset(dx, dy));
  }

  void _paintConnector(Canvas canvas, DiagramConnector connector) {
    final from = document.shapeById(connector.fromId);
    final to = document.shapeById(connector.toId);
    if (from == null || to == null) return;
    final start = from.anchorPoint(connector.fromAnchor);
    final end = to.anchorPoint(connector.toAnchor);
    final color = DiagramStyle.color(connector.strokeColor);
    final paint = Paint()
      ..color = connector.id == selectedConnectorId
          ? BrandPainter.selection
          : color
      ..strokeWidth = connector.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = switch (connector.kind) {
      ConnectorKind.straight =>
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy),
      ConnectorKind.curve =>
        Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx,
            (start.dy + end.dy) / 2,
            end.dx,
            (start.dy + end.dy) / 2,
            end.dx,
            end.dy,
          ),
      ConnectorKind.elbow => _elbowPath(start, end),
    };

    if (connector.dashed) {
      _drawDashedPath(canvas, path, paint, 6, 4);
    } else {
      canvas.drawPath(path, paint);
    }

    if (connector.arrowEnd) {
      _arrowHead(canvas, start, end, color, connector.strokeWidth);
    }
    if (connector.arrowStart) {
      _arrowHead(canvas, end, start, color, connector.strokeWidth);
    }

    if (connector.label.trim().isNotEmpty) {
      final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final painter = TextPainter(
        text: TextSpan(
          text: connector.label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final bg = Rect.fromCenter(
        center: midpoint,
        width: painter.width + 8,
        height: painter.height + 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bg, const Radius.circular(3)),
        Paint()
          ..color = dark ? const Color(0xFF161412) : const Color(0xFFFAF7F0),
      );
      painter.paint(
        canvas,
        Offset(
          midpoint.dx - painter.width / 2,
          midpoint.dy - painter.height / 2,
        ),
      );
    }
  }

  Path _elbowPath(Offset start, Offset end) {
    final midX = (start.dx + end.dx) / 2;
    return Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(midX, start.dy)
      ..lineTo(midX, end.dy)
      ..lineTo(end.dx, end.dy);
  }

  void _arrowHead(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color,
    double width,
  ) {
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    final size = 8 + width * 2;
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - size * math.cos(angle - math.pi / 7),
        to.dy - size * math.sin(angle - math.pi / 7),
      )
      ..lineTo(
        to.dx - size * math.cos(angle + math.pi / 7),
        to.dy - size * math.sin(angle + math.pi / 7),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _strokePath(Canvas canvas, Path path, Paint paint, bool dashed) {
    if (dashed) {
      _drawDashedPath(canvas, path, paint, 8, 5);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double dash,
    double gap,
  ) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  void _paintSelection(Canvas canvas, DiagramShape shape) {
    final rect = shape.rect.inflate(2);
    final paint = Paint()
      ..color = BrandPainter.selection
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, paint);
    final handle = Paint()..color = BrandPainter.selection;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: 7, height: 7),
        handle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DiagramPainter oldDelegate) => true;
}

class BrandPainter {
  static const selection = Color(0xFF3F7AD6);
}

Uint8List? imageBytesFromBase64(String? data) {
  if (data == null || data.isEmpty) return null;
  try {
    final clean = data.contains(',') ? data.split(',').last : data;
    return base64Decode(clean.replaceAll(RegExp(r'\s'), ''));
  } catch (_) {
    return null;
  }
}
