// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/material.dart';

/// Kumiho Browser Theme Constants
class KumihoTheme {
  KumihoTheme._();

  // ==================== COLORS ==================== //
  
  // Primary brand colors (same for both themes)
  static const Color primary = Color(0xFF6B4EFF);
  static const Color primaryLight = Color(0xFF9B7DFF);
  static const Color primaryDark = Color(0xFF4A35B3);

  // ==================== DARK THEME COLORS ==================== //
  
  // Background colors
  static const Color background = Color(0xFF1A1A1A);
  static const Color backgroundMain = Color(0xFF1A1A1A);
  static const Color backgroundSecondary = Color(0xFF242424);
  static const Color backgroundHeader = Color(0xFF242424);
  static const Color backgroundSidebar = Color(0xFF1E1E1E);
  static const Color backgroundCard = Color(0xFF2D2D2D);
  static const Color backgroundList = Color(0xFF2A2A2A);
  static const Color surface = Color(0xFF242424);
  static const Color surfaceLight = Color(0xFF2A2A2A);
  static const Color surfaceLighter = Color(0xFF2D2D2D);
  static const Color surfaceBorder = Color(0xFF3A3A3A);
  static const Color surfaceBorderLight = Color(0xFF404040);

  // Accent colors
  static const Color accentPrimary = Color(0xFF6B4EFF);
  static const Color accentSecondary = Color(0xFF9B7DFF);

  // Border colors
  static const Color border = Color(0xFF3A3A3A);
  static const Color borderColor = Color(0xFF3A3A3A);
  static const Color borderLight = Color(0xFF404040);
  static const Color borderDark = Color(0xFF2A2A2A);
  static const Color borderSubtle = Color(0xFF363636);

  // Sidebar colors (legacy aliases)
  static const Color sidebarBackground = Color(0xFF1E1E1E);
  static const Color sidebarHeader = Color(0xFF242424);
  static const Color sidebarBorder = Color(0xFF2A2A2A);

  // Text colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF); // white70
  static const Color textTertiary = Color(0x61FFFFFF); // white38
  static const Color textMuted = Color(0x8AFFFFFF); // white54
  static const Color textDimmed = Color(0x61FFFFFF); // white38
  static const Color textVeryDimmed = Color(0x3DFFFFFF); // white24
  static const Color textDisabled = Color(0x3DFFFFFF); // white24

  // Status colors (same for both themes)
  static const Color success = Color(0xFF00B894);
  static const Color info = Color(0xFF0984E3);
  static const Color warning = Color(0xFFFDAB46);
  static const Color error = Color(0xFFD63031);

  // Tag colors (same for both themes)
  static const Color tagLatest = Color(0xFF00B894);
  static const Color tagApproved = Color(0xFF0984E3);
  static const Color tagWip = Color(0xFFFDAB46);
  static const Color tagDefault = Color(0xFF636E72);

  /// Available swatch colors for playlist labels.
  ///
  /// Keep this list limited and sourced from existing theme tokens.
  static const List<Color> playlistSwatchColors = <Color>[
    primary,
    success,
    info,
    warning,
    error,
    tagDefault,
    primaryLight,
  ];

  // ==================== LIGHT THEME COLORS ==================== //
  // Darker gray light theme - not harsh white, more professional
  
  static const Color lightBackground = Color(0xFFD0D0D6);       // Darker gray base
  static const Color lightBackgroundMain = Color(0xFFCCCCD4);   // Grid/main area - darker for cards to stand out
  static const Color lightBackgroundSecondary = Color(0xFFDCDCE4); // Slightly lighter
  static const Color lightBackgroundHeader = Color(0xFFD8D8E0);  // Header background
  static const Color lightBackgroundSidebar = Color(0xFFC8C8D0); // Sidebar - darker
  static const Color lightBackgroundCard = Color(0xFFE8E8F0);    // Cards - lighter for contrast
  static const Color lightBackgroundList = Color(0xFFD4D4DC);    // List items alternate
  static const Color lightSurface = Color(0xFFE0E0E8);
  static const Color lightSurfaceLight = Color(0xFFE8E8F0);
  static const Color lightSurfaceLighter = Color(0xFFECECF4);
  static const Color lightSurfaceBorder = Color(0xFFB8B8C4);
  static const Color lightSurfaceBorderLight = Color(0xFFC4C4D0);

  static const Color lightBorder = Color(0xFFB0B0BC);
  static const Color lightBorderLight = Color(0xFFBCBCC8);
  static const Color lightBorderDark = Color(0xFFA4A4B0);
  static const Color lightBorderSubtle = Color(0xFFC0C0CC);

  static const Color lightTextPrimary = Color(0xFF1A1A1E);       // Near black
  static const Color lightTextSecondary = Color(0xFF3A3A44);     // Dark gray (darker)
  static const Color lightTextTertiary = Color(0xFF4A4A56);      // Medium gray (darker)
  static const Color lightTextMuted = Color(0xFF5A5A66);         // Muted gray (darker)
  static const Color lightTextDimmed = Color(0xFF6A6A76);        // Dimmed gray (much darker)
  static const Color lightTextVeryDimmed = Color(0xFF8A8A96);    // Very dimmed (darker)
  static const Color lightTextDisabled = Color(0xFFA0A0AC);      // Disabled (darker)

  // ==================== SIZES ==================== //

  // Header
  static const double headerHeight = 48.0;
  static const double logoSize = 80.0;

  // Sidebar
  static const double sidebarExpandedWidth = 200.0;
  static const double sidebarCollapsedWidth = 40.0;
  static const double playlistItemHeight = 40.0;

  // Detail panel
  static const double detailPanelMinWidth = 280.0;
  static const double detailPanelMaxWidth = 500.0;
  static const double detailPanelDefaultWidth = 320.0;

  // Bottom playlist
  static const double playlistAreaMinHeight = 80.0;
  static const double playlistAreaMaxHeight = 300.0;
  static const double playlistAreaDefaultHeight = 140.0;
  static const double playlistHeaderHeight = 28.0;

  // Clip container
  static const double clipMinSize = 100.0;
  static const double clipMaxSize = 240.0;
  static const double clipBorderRadius = 8.0;

  // Drop zones
  static const double dropZoneWidth = 12.0;
  static const double dropZoneHoverWidth = 24.0;

  // ==================== SPACING ==================== //

  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 24.0;
  
  // Compact mode spacing (reduced by ~40%)
  static const double compactSpacingXs = 2.0;
  static const double compactSpacingSm = 5.0;
  static const double compactSpacingMd = 8.0;
  static const double compactSpacingLg = 10.0;
  static const double compactSpacingXl = 16.0;

  // ==================== BORDER RADIUS ==================== //

  static const double radiusSm = 4.0;
  static const double radiusMd = 6.0;
  static const double radiusLg = 8.0;
  static const double radiusXl = 10.0;

  // ==================== ANIMATION ==================== //

  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 200);
  static const Duration animationSlow = Duration(milliseconds: 300);

  // ==================== THEME DATA ==================== //

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primaryLight,
        surface: surface,
      ),
      dividerColor: surfaceBorder,
      hoverColor: primary.withAlpha(26),
      splashColor: primary.withAlpha(51),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primaryLight,
        surface: lightSurface,
      ),
      dividerColor: lightBorder,
      hoverColor: primary.withAlpha(26),
      splashColor: primary.withAlpha(51),
    );
  }

  // ==================== THEME-AWARE COLOR ACCESSORS ==================== //
  
  /// Get theme-aware colors based on current brightness
  static KumihoColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? KumihoColors.dark() : KumihoColors.light();
  }

  /// Check if current theme is dark mode
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  // ==================== HELPER METHODS ==================== //

  static Color getTagColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'latest':
        return tagLatest;
      case 'approved':
        return tagApproved;
      case 'wip':
        return tagWip;
      default:
        return tagDefault;
    }
  }

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: surfaceLight,
    borderRadius: BorderRadius.circular(radiusLg),
    border: Border.all(color: surfaceBorder, width: 1),
  );

  static BoxDecoration get selectedCardDecoration => BoxDecoration(
    color: surfaceLight,
    borderRadius: BorderRadius.circular(radiusLg),
    border: Border.all(color: primary, width: 2),
  );
}

/// Theme-aware color accessor class
/// Usage: final colors = KumihoTheme.of(context);
/// Then: colors.background, colors.textPrimary, etc.
class KumihoColors {
  final Color background;
  final Color backgroundMain;
  final Color backgroundSecondary;
  final Color backgroundHeader;
  final Color backgroundSidebar;
  final Color backgroundCard;
  final Color backgroundList;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceLighter;
  final Color surfaceBorder;
  final Color surfaceBorderLight;
  final Color border;
  final Color borderLight;
  final Color borderDark;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textMuted;
  final Color textDimmed;
  final Color textVeryDimmed;
  final Color textDisabled;

  const KumihoColors._({
    required this.background,
    required this.backgroundMain,
    required this.backgroundSecondary,
    required this.backgroundHeader,
    required this.backgroundSidebar,
    required this.backgroundCard,
    required this.backgroundList,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceLighter,
    required this.surfaceBorder,
    required this.surfaceBorderLight,
    required this.border,
    required this.borderLight,
    required this.borderDark,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.textDimmed,
    required this.textVeryDimmed,
    required this.textDisabled,
  });

  factory KumihoColors.dark() => const KumihoColors._(
    background: KumihoTheme.background,
    backgroundMain: KumihoTheme.backgroundMain,
    backgroundSecondary: KumihoTheme.backgroundSecondary,
    backgroundHeader: KumihoTheme.backgroundHeader,
    backgroundSidebar: KumihoTheme.backgroundSidebar,
    backgroundCard: KumihoTheme.backgroundCard,
    backgroundList: KumihoTheme.backgroundList,
    surface: KumihoTheme.surface,
    surfaceLight: KumihoTheme.surfaceLight,
    surfaceLighter: KumihoTheme.surfaceLighter,
    surfaceBorder: KumihoTheme.surfaceBorder,
    surfaceBorderLight: KumihoTheme.surfaceBorderLight,
    border: KumihoTheme.border,
    borderLight: KumihoTheme.borderLight,
    borderDark: KumihoTheme.borderDark,
    borderSubtle: KumihoTheme.borderSubtle,
    textPrimary: KumihoTheme.textPrimary,
    textSecondary: KumihoTheme.textSecondary,
    textTertiary: KumihoTheme.textTertiary,
    textMuted: KumihoTheme.textMuted,
    textDimmed: KumihoTheme.textDimmed,
    textVeryDimmed: KumihoTheme.textVeryDimmed,
    textDisabled: KumihoTheme.textDisabled,
  );

  factory KumihoColors.light() => const KumihoColors._(
    background: KumihoTheme.lightBackground,
    backgroundMain: KumihoTheme.lightBackgroundMain,
    backgroundSecondary: KumihoTheme.lightBackgroundSecondary,
    backgroundHeader: KumihoTheme.lightBackgroundHeader,
    backgroundSidebar: KumihoTheme.lightBackgroundSidebar,
    backgroundCard: KumihoTheme.lightBackgroundCard,
    backgroundList: KumihoTheme.lightBackgroundList,
    surface: KumihoTheme.lightSurface,
    surfaceLight: KumihoTheme.lightSurfaceLight,
    surfaceLighter: KumihoTheme.lightSurfaceLighter,
    surfaceBorder: KumihoTheme.lightSurfaceBorder,
    surfaceBorderLight: KumihoTheme.lightSurfaceBorderLight,
    border: KumihoTheme.lightBorder,
    borderLight: KumihoTheme.lightBorderLight,
    borderDark: KumihoTheme.lightBorderDark,
    borderSubtle: KumihoTheme.lightBorderSubtle,
    textPrimary: KumihoTheme.lightTextPrimary,
    textSecondary: KumihoTheme.lightTextSecondary,
    textTertiary: KumihoTheme.lightTextTertiary,
    textMuted: KumihoTheme.lightTextMuted,
    textDimmed: KumihoTheme.lightTextDimmed,
    textVeryDimmed: KumihoTheme.lightTextVeryDimmed,
    textDisabled: KumihoTheme.lightTextDisabled,
  );
}
