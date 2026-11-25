import 'package:flutter/material.dart';

/// Colour tokens from design_system/colours.md. Do not invent new colours.
class DzColors {
  DzColors._();
  static const bg = Color(0xFF0D1117);
  static const bg2 = Color(0xFF131A23);
  static const card = Color(0xFF192330);
  static const elevated = Color(0xFF202C3A);
  static const accent = Color(0xFF16C784);
  static const accent2 = Color(0xFF36A3FF);
  static const warning = Color(0xFFF0B90B);
  static const danger = Color(0xFFFF4D5A);
  static const text = Color(0xFFF5F7FA);
  static const text2 = Color(0xFF929EAD);
  static const border = Color(0xFF283646);
  static const onAccent = Color(0xFF04120C);

  /// Mixes [over] into [base] at [pct] (0..1). Used for status pills/tiles.
  static Color tint(Color base, Color over, double pct) =>
      Color.alphaBlend(over.withAlpha((pct * 255).round()), base);
}

/// Typography tokens from design_system/typography.md (Inter, Roboto fallback).
class DzText {
  DzText._();
  static const _family = 'Inter';
  static const _fallback = ['Roboto'];

  static TextStyle _s(double size, FontWeight w, Color c,
          {double? height, double? letterSpacing, bool tabular = false}) =>
      TextStyle(
        fontFamily: _family,
        fontFamilyFallback: _fallback,
        fontSize: size,
        fontWeight: w,
        color: c,
        height: height,
        letterSpacing: letterSpacing,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      );

  static TextStyle screenTitle() => _s(26, FontWeight.w700, DzColors.text);
  static TextStyle sheetTitle() => _s(20, FontWeight.w700, DzColors.text);
  static TextStyle displayPrice({Color color = DzColors.text}) =>
      _s(30, FontWeight.w700, color, tabular: true);
  static TextStyle cardPrice({Color color = DzColors.text}) =>
      _s(21, FontWeight.w700, color, tabular: true);
  static TextStyle pair() => _s(17, FontWeight.w700, DzColors.text);
  static TextStyle body(
          {Color color = DzColors.text, FontWeight w = FontWeight.w400}) =>
      _s(14, w, color);
  static TextStyle label({Color color = DzColors.text2}) =>
      _s(12, FontWeight.w600, color);
  static TextStyle caption(
          {Color color = DzColors.text2, double letterSpacing = 0.4}) =>
      _s(11, FontWeight.w600, color, letterSpacing: letterSpacing);
  static TextStyle pill(Color color) =>
      _s(10, FontWeight.w700, color, letterSpacing: 0.6);
  static TextStyle button({Color color = DzColors.onAccent}) =>
      _s(16, FontWeight.w700, color);
}

/// Optional: AI 4 may apply this to the MaterialApp. Screens do not depend on it.
ThemeData buildDrezaTheme() => ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: DzColors.bg,
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Roboto'],
      colorScheme: const ColorScheme.dark(
        primary: DzColors.accent,
        secondary: DzColors.accent2,
        error: DzColors.danger,
        surface: DzColors.bg2,
        onPrimary: DzColors.onAccent,
        onSurface: DzColors.text,
      ),
    );
