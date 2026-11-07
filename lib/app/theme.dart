import 'package:flutter/material.dart';

import '../core/constants.dart';

export '../core/constants.dart' show BrandColors;

class AppTheme {
  static ThemeData light({double fontScale = 1}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.brass,
      brightness: Brightness.light,
    );
    return _base(scheme, fontScale);
  }

  static ThemeData dark({double fontScale = 1}) {
    const scheme = ColorScheme.dark(
      primary: BrandColors.brassLight,
      onPrimary: BrandColors.charcoal,
      secondary: BrandColors.brass,
      surface: BrandColors.charcoal,
      onSurface: Color(0xFFEDE7DD),
      error: BrandColors.danger,
    );
    return _base(scheme, fontScale);
  }

  static ThemeData _base(ColorScheme scheme, double fontScale) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? BrandColors.charcoal
          : const Color(0xFFF7F4EE),
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
      textTheme: ThemeData(brightness: scheme.brightness).textTheme
          .apply(fontSizeFactor: fontScale),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: isDark
            ? BrandColors.charcoal
            : const Color(0xFFF7F4EE),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? const Color(0xFF3A3632) : const Color(0xFFE4DDD0),
          ),
        ),
        color: isDark ? BrandColors.charcoalCard : Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF232120) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF3A3632) : const Color(0xFFE4DDD0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF3A3632) : const Color(0xFFE4DDD0),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF3A3632) : const Color(0xFFE4DDD0),
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: isDark ? const Color(0xFF3A3632) : const Color(0xFFE4DDD0),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark
            ? BrandColors.charcoalSoft
            : const Color(0xFFEDE7DC),
        indicatorColor: BrandColors.brass.withValues(alpha: 0.28),
        selectedIconTheme: const IconThemeData(color: BrandColors.brass),
        selectedLabelTextStyle: TextStyle(
          color: isDark ? BrandColors.brassLight : const Color(0xFF7A5722),
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: isDark ? BrandColors.charcoalSoft : Colors.white,
        indicatorColor: BrandColors.brass.withValues(alpha: 0.25),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
