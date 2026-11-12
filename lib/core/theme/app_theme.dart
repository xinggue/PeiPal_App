import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const primarySeed = Color(0xFF1976D2);

  /// 全局列表卡片标准统一外间距（卡片之间自然形成 8dp 间隙，左右各 12dp）
  static const cardListMargin = EdgeInsets.symmetric(horizontal: 12, vertical: 4);

  static const List<String> _windowsCjkFallback = [
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Segoe UI',
  ];

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primarySeed,
      brightness: Brightness.light,
    );
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    final String? uiFont = windows ? 'Microsoft YaHei UI' : null;
    final List<String>? uiFallback = windows ? _windowsCjkFallback : null;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      fontFamily: uiFont,
      fontFamilyFallback: uiFallback,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      
      // AppBar 样式规范
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
          fontFamily: uiFont,
          fontFamilyFallback: uiFallback,
        ),
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
          size: 22,
        ),
      ),

      // 卡片统一规范
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),

      // 列表项统一样式
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: false,
        minLeadingWidth: 24,
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          fontFamily: uiFont,
          fontFamilyFallback: uiFallback,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurfaceVariant,
          fontFamily: uiFont,
          fontFamilyFallback: uiFallback,
        ),
      ),

      // 对话框统一圆角与质感
      dialogTheme: DialogThemeData(
        elevation: 3,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
          fontFamily: uiFont,
          fontFamilyFallback: uiFallback,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurfaceVariant,
          fontFamily: uiFont,
          fontFamilyFallback: uiFallback,
        ),
      ),

      // 底部弹窗统一圆角与抓手
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 4,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: colorScheme.outlineVariant,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // 输入框默认统一样式
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.error,
          ),
        ),
      ),

      // 统一按钮圆角
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),

      // SnackBar 兜底规范 (浮动、圆角、不贴底)
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 3,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),

      // 平滑丝滑页面过渡 (全平台统一轻量无离屏快照的 Cupertino 左右推入动画，与 iOS 保持一致流畅度)
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        thickness: 0.8,
        space: 1,
      ),
    );
  }
}
