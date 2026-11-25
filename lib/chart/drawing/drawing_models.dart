import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;


/// Anchor in market space (never pixels) so shapes survive zoom/pan/TF changes.
@immutable
class DrawingPoint {
  const DrawingPoint({required this.time, required this.price});

  final int time; // epoch seconds
  final double price;

  DrawingPoint copyWith({int? time, double? price}) => DrawingPoint(
        time: time ?? this.time,
        price: price ?? this.price,
      );

  Map<String, Object?> toJson() => {'t': time, 'p': price};

  factory DrawingPoint.fromJson(Object? json) {
    if (json is! Map) {
      return const DrawingPoint(time: 0, price: 0);
    }
    final t = json['t'];
    final p = json['p'];
    return DrawingPoint(
      time: t is int ? t : (t is num ? t.round() : 0),
      price: p is num ? p.toDouble() : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DrawingPoint && other.time == time && other.price == price;

  @override
  int get hashCode => Object.hash(time, price);
}

enum DrawingType { trendline, rectangle, horizontalLine }

@immutable
class DrawingStyle {
  const DrawingStyle({
    this.colorValue = 0xFF36A3FF, // DzColors.accent2
    this.width = 1.5,
    this.fillAlpha = 0x33,
    this.extendRight = false,
  });

  final int colorValue;
  final double width;
  final double fillAlpha; // 0..255 for rectangle fill
  final bool extendRight; // trendline ray

  Color get color => Color(colorValue);

  DrawingStyle copyWith({
    int? colorValue,
    double? width,
    double? fillAlpha,
    bool? extendRight,
  }) =>
      DrawingStyle(
        colorValue: colorValue ?? this.colorValue,
        width: width ?? this.width,
        fillAlpha: fillAlpha ?? this.fillAlpha,
        extendRight: extendRight ?? this.extendRight,
      );

  Map<String, Object?> toJson() => {
        'c': colorValue,
        'w': width,
        'fa': fillAlpha,
        'er': extendRight,
      };

  factory DrawingStyle.fromJson(Object? json) {
    if (json is! Map) return const DrawingStyle();
    return DrawingStyle(
      colorValue: json['c'] is int ? json['c'] as int : 0xFF36A3FF,
      width: json['w'] is num ? (json['w'] as num).toDouble() : 1.5,
      fillAlpha: json['fa'] is num ? (json['fa'] as num).toDouble() : 0x33,
      extendRight: json['er'] == true,
    );
  }

  static const List<int> presetColors = [
    0xFF36A3FF, // accent2 blue
    0xFFF0B90B, // warning amber
    0xFF16C784, // accent green
    0xFFFF4D5A, // danger
    0xFF929EAD, // text2
    0xFFF5F7FA, // text
  ];

  static DrawingStyle defaultsFor(DrawingType type) {
    switch (type) {
      case DrawingType.trendline:
        return const DrawingStyle(colorValue: 0xFF36A3FF, width: 1.5);
      case DrawingType.rectangle:
        return const DrawingStyle(
          colorValue: 0xFFF0B90B,
          width: 1.5,
          fillAlpha: 0x33,
        );
      case DrawingType.horizontalLine:
        return const DrawingStyle(colorValue: 0xFF929EAD, width: 1);
    }
  }
}

@immutable
class DrawingShape {
  const DrawingShape({
    required this.id,
    required this.type,
    required this.points,
    required this.style,
  });

  final String id;
  final DrawingType type;
  final List<DrawingPoint> points;
  final DrawingStyle style;

  DrawingShape copyWith({
    List<DrawingPoint>? points,
    DrawingStyle? style,
  }) =>
      DrawingShape(
        id: id,
        type: type,
        points: points ?? this.points,
        style: style ?? this.style,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'type': type.name,
        'pts': [for (final p in points) p.toJson()],
        'style': style.toJson(),
      };

  /// Tolerant parser — returns null for unusable shapes (never throws).
  static DrawingShape? tryFromJson(Object? json) {
    try {
      if (json is! Map) return null;
      final id = json['id'];
      if (id is! String || id.isEmpty) return null;
      final typeName = json['type'];
      DrawingType? type;
      for (final t in DrawingType.values) {
        if (t.name == typeName) {
          type = t;
          break;
        }
      }
      if (type == null) return null;
      final rawPts = json['pts'];
      if (rawPts is! List || rawPts.isEmpty) return null;
      final pts = <DrawingPoint>[
        for (final p in rawPts) DrawingPoint.fromJson(p),
      ];
      // Validate minimum points.
      if (type == DrawingType.horizontalLine && pts.isEmpty) return null;
      if (type != DrawingType.horizontalLine && pts.length < 2) return null;
      return DrawingShape(
        id: id,
        type: type,
        points: pts,
        style: DrawingStyle.fromJson(json['style']),
      );
    } catch (_) {
      return null;
    }
  }
}
