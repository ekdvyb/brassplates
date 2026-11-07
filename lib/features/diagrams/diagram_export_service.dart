import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/enums.dart';
import 'diagram_model.dart';
import 'diagram_painter.dart';

class DiagramExportService {
  const DiagramExportService._();

  static Rect documentBounds(DiagramDocument document) {
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final shape in document.shapes) {
      left = left < shape.x ? left : shape.x;
      top = top < shape.y ? top : shape.y;
      right = right > shape.x + shape.width ? right : shape.x + shape.width;
      bottom = bottom > shape.y + shape.height
          ? bottom
          : shape.y + shape.height;
      for (final point in shape.points) {
        left = left < point.x ? left : point.x;
        top = top < point.y ? top : point.y;
        right = right > point.x ? right : point.x;
        bottom = bottom > point.y ? bottom : point.y;
      }
    }
    if (!left.isFinite || !top.isFinite) {
      return const Rect.fromLTWH(0, 0, 900, 600);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Future<ui.Image> renderImage(
    DiagramDocument document, {
    double scale = 2,
    bool dark = false,
  }) async {
    final bounds = documentBounds(document).inflate(40);
    final width = bounds.width;
    final height = bounds.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = dark ? const Color(0xFF161412) : Colors.white,
    );
    final painter = DiagramPainter(
      document: document,
      viewport: DiagramViewport(dx: -bounds.left, dy: -bounds.top, scale: 1),
      showGrid: false,
      dark: dark,
      exporting: true,
    );
    painter.paint(canvas, Size(width, height));
    final picture = recorder.endRecording();
    return picture.toImage((width * scale).ceil(), (height * scale).ceil());
  }

  static Future<List<int>> png(
    DiagramDocument document, {
    double scale = 2,
    bool dark = false,
  }) async {
    final image = await renderImage(document, scale: scale, dark: dark);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static Future<List<int>> pdf(
    DiagramDocument document, {
    bool dark = false,
  }) async {
    final bounds = documentBounds(document).inflate(40);
    final image = await renderImage(document, scale: 2, dark: dark);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(bounds.width, bounds.height, marginAll: 0),
        build: (context) => pw.Image(
          pw.MemoryImage(data!.buffer.asUint8List()),
          fit: pw.BoxFit.contain,
        ),
      ),
    );
    return pdf.save();
  }

  static String svg(DiagramDocument document, {bool dark = false}) {
    final bounds = documentBounds(document).inflate(30);
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="${bounds.width.toStringAsFixed(0)}" height="${bounds.height.toStringAsFixed(0)}" viewBox="${bounds.left.toStringAsFixed(1)} ${bounds.top.toStringAsFixed(1)} ${bounds.width.toStringAsFixed(1)} ${bounds.height.toStringAsFixed(1)}">',
      )
      ..writeln(
        '<rect x="${bounds.left}" y="${bounds.top}" width="${bounds.width}" height="${bounds.height}" fill="${dark ? '#161412' : '#FFFFFF'}"/>',
      );

    for (final connector in document.connectors) {
      final from = document.shapeById(connector.fromId);
      final to = document.shapeById(connector.toId);
      if (from == null || to == null) continue;
      final start = from.anchorPoint(connector.fromAnchor);
      final end = to.anchorPoint(connector.toAnchor);
      buffer.writeln(
        '<line x1="${start.dx}" y1="${start.dy}" x2="${end.dx}" y2="${end.dy}" stroke="${connector.strokeColor}" stroke-width="${connector.strokeWidth}"${connector.dashed ? ' stroke-dasharray="6 4"' : ''}/>',
      );
      if (connector.label.trim().isNotEmpty) {
        buffer.writeln(
          '<text x="${(start.dx + end.dx) / 2}" y="${(start.dy + end.dy) / 2}" fill="${connector.strokeColor}" font-size="11" text-anchor="middle">${_escape(connector.label)}</text>',
        );
      }
    }

    for (final shape in document.shapes) {
      final fill = shape.style.fillColor;
      final stroke = shape.style.strokeColor;
      final common =
          'fill="$fill" stroke="$stroke" stroke-width="${shape.style.strokeWidth}"${shape.style.dashed ? ' stroke-dasharray="8 5"' : ''}';
      switch (shape.type) {
        case DiagramShapeType.ellipse:
        case DiagramShapeType.user:
          buffer.writeln(
            '<ellipse cx="${shape.center.dx}" cy="${shape.center.dy}" rx="${shape.width / 2}" ry="${shape.height / 2}" $common/>',
          );
        case DiagramShapeType.diamond:
          buffer.writeln(
            '<polygon points="${shape.center.dx},${shape.y} ${shape.x + shape.width},${shape.center.dy} ${shape.center.dx},${shape.y + shape.height} ${shape.x},${shape.center.dy}" $common/>',
          );
        case DiagramShapeType.arrow:
        case DiagramShapeType.line:
        case DiagramShapeType.freehand:
          if (shape.points.length < 2) break;
          final points = shape.points
              .map((point) => '${point.x},${point.y}')
              .join(' ');
          buffer.writeln(
            '<polyline points="$points" fill="none" stroke="$stroke" stroke-width="${shape.style.strokeWidth}"/>',
          );
        case DiagramShapeType.text:
          break;
        default:
          buffer.writeln(
            '<rect x="${shape.x}" y="${shape.y}" width="${shape.width}" height="${shape.height}" rx="${shape.style.cornerRadius}" $common/>',
          );
      }
      if (shape.type != DiagramShapeType.arrow &&
          shape.type != DiagramShapeType.line &&
          shape.type != DiagramShapeType.freehand &&
          shape.label.trim().isNotEmpty) {
        buffer.writeln(
          '<text x="${shape.center.dx}" y="${shape.center.dy}" fill="${shape.style.textColor}" font-size="${shape.style.fontSize}" text-anchor="middle" dominant-baseline="middle">${_escape(shape.label)}</text>',
        );
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String toBase64Png(List<int> bytes) => base64Encode(bytes);
}
