import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/page_transitions.dart';
import '../tokens/colors.dart';
import '../tokens/dimens.dart';
import 'ghina_tokens.dart';
import 'typography.dart';

/// Entry points for the app theme.
///
/// ```dart
/// MaterialApp.router(
///   theme: GhinaTheme.light(),
///   darkTheme: GhinaTheme.dark(),
///   themeMode: ThemeMode.system,
/// );
/// ```
abstract final class GhinaTheme {
  static ThemeData light() => _build(GhinaTokens.light);
  static ThemeData dark() => _build(GhinaTokens.dark);

  static ThemeData _build(GhinaTokens g) {
    final isDark = g.isDark;
    final scheme = ColorScheme(
      brightness: g.brightness,
      primary: GhinaColors.green.base,
      onPrimary: Colors.white,
      primaryContainer: g.tint(GhinaColors.green),
      onPrimaryContainer: isDark
          ? GhinaColors.lime.base
          : GhinaColors.green.edge,
      secondary: GhinaColors.blue.base,
      onSecondary: Colors.white,
      secondaryContainer: g.tint(GhinaColors.blue),
      onSecondaryContainer: GhinaColors.blue.edge,
      tertiary: GhinaColors.purple.base,
      onTertiary: Colors.white,
      error: GhinaColors.red.base,
      onError: Colors.white,
      errorContainer: g.tint(GhinaColors.red),
      onErrorContainer: GhinaColors.red.edge,
      surface: g.surface,
      onSurface: g.textPrimary,
      onSurfaceVariant: g.textSecondary,
      surfaceContainerLowest: g.background,
      surfaceContainerLow: g.surfaceAlt,
      surfaceContainer: g.surfaceAlt,
      surfaceContainerHigh: isDark
          ? GhinaColors.darkSurfaceAlt
          : GhinaColors.polar,
      surfaceContainerHighest: g.border,
      outline: g.border,
      outlineVariant: g.border,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: isDark ? GhinaColors.darkTextPrimary : GhinaColors.eel,
      onInverseSurface: isDark ? GhinaColors.darkBackground : Colors.white,
      inversePrimary: GhinaColors.lime.base,
    );

    final text = GhinaType.textTheme(g.textPrimary, g.textSecondary);
    const r = GhinaRadii.rLg;
    OutlineInputBorder inBorder(Color c, [double w = GhinaDepth.border]) =>
        OutlineInputBorder(
          borderRadius: r,
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: g.brightness,
      colorScheme: scheme,
      fontFamily: GhinaType.family,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: g.background,
      canvasColor: g.background,
      dividerColor: g.border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      extensions: [g],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: GhinaPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: GhinaPageTransitionsBuilder(),
          TargetPlatform.windows: GhinaPageTransitionsBuilder(),
        },
      ),
      iconTheme: IconThemeData(color: g.textSecondary, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: g.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: g.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GhinaType.h2.copyWith(color: g.textPrimary),
        iconTheme: IconThemeData(color: g.textMuted, size: 28),
        actionsIconTheme: IconThemeData(color: g.textMuted, size: 26),
        shape: Border(
          bottom: BorderSide(color: g.border, width: GhinaDepth.border),
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: g.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: g.tint(GhinaColors.blue),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: GhinaRadii.rMd,
          side: BorderSide(
            color: GhinaColors.blue.tintBorder(g.brightness),
            width: 2,
          ),
        ),
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => GhinaType.caption.copyWith(
            color: s.contains(WidgetState.selected)
                ? GhinaColors.blue.base
                : g.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 28,
            color: s.contains(WidgetState.selected)
                ? GhinaColors.blue.base
                : g.textMuted,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: g.background,
        selectedItemColor: GhinaColors.blue.base,
        unselectedItemColor: g.textMuted,
        selectedLabelStyle: GhinaType.caption,
        unselectedLabelStyle: GhinaType.caption,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: g.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: GhinaType.bodyL.copyWith(color: g.textMuted),
        labelStyle: GhinaType.body.w(700).copyWith(color: g.textSecondary),
        floatingLabelStyle: GhinaType.body
            .w(800)
            .copyWith(color: GhinaColors.blue.base),
        helperStyle: GhinaType.caption.copyWith(color: g.textSecondary),
        errorStyle: GhinaType.caption.copyWith(color: GhinaColors.red.base),
        prefixIconColor: g.textMuted,
        suffixIconColor: g.textMuted,
        border: inBorder(g.border),
        enabledBorder: inBorder(g.border),
        focusedBorder: inBorder(GhinaColors.blue.base),
        errorBorder: inBorder(GhinaColors.red.base),
        focusedErrorBorder: inBorder(GhinaColors.red.base),
        disabledBorder: inBorder(g.border.withValues(alpha: 0.5)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: GhinaColors.blue.base,
        selectionColor: GhinaColors.blue.base.withValues(alpha: 0.3),
        selectionHandleColor: GhinaColors.blue.base,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: g.surface,
        selectedColor: g.tint(GhinaColors.blue),
        disabledColor: g.disabled,
        labelStyle: GhinaType.body.w(800).copyWith(color: g.textSecondary),
        secondaryLabelStyle: GhinaType.body
            .w(800)
            .copyWith(color: GhinaColors.blue.base),
        side: BorderSide(color: g.border, width: 2),
        shape: const RoundedRectangleBorder(borderRadius: GhinaRadii.rMd),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        checkmarkColor: GhinaColors.blue.base,
        showCheckmark: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: GhinaRadii.rXxl,
          side: BorderSide(color: g.border, width: 2),
        ),
        titleTextStyle: GhinaType.h2.copyWith(color: g.textPrimary),
        contentTextStyle: GhinaType.bodyL.copyWith(color: g.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: g.surface,
        modalBackgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: g.border,
        dragHandleSize: const Size(48, 6),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(GhinaRadii.xxl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.eel,
        contentTextStyle: GhinaType.body.w(700).copyWith(color: Colors.white),
        actionTextColor: GhinaColors.lime.base,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: GhinaRadii.rLg,
          side: BorderSide(
            color: isDark ? GhinaColors.darkBorder : Colors.black,
            width: 0,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? GhinaColors.green.base
              : g.border,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? GhinaColors.green.edge
              : g.borderEdge,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(2),
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: GhinaColors.green.base,
                )
              : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? GhinaColors.blue.base
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: g.border, width: 2),
        shape: const RoundedRectangleBorder(borderRadius: GhinaRadii.rSm),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? GhinaColors.blue.base
              : g.border,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: GhinaColors.green.base,
        linearTrackColor: g.border,
        circularTrackColor: g.border,
        linearMinHeight: 12,
        borderRadius: GhinaRadii.rPill,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: GhinaColors.green.base,
        inactiveTrackColor: g.border,
        thumbColor: GhinaColors.green.base,
        overlayColor: GhinaColors.green.base.withValues(alpha: 0.15),
        trackHeight: 10,
      ),
      dividerTheme: DividerThemeData(color: g.border, thickness: 2, space: 2),
      listTileTheme: ListTileThemeData(
        iconColor: g.textSecondary,
        textColor: g.textPrimary,
        titleTextStyle: GhinaType.h3.copyWith(color: g.textPrimary),
        subtitleTextStyle: GhinaType.bodyS.copyWith(color: g.textSecondary),
        shape: const RoundedRectangleBorder(borderRadius: GhinaRadii.rLg),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: GhinaColors.blue.base,
        unselectedLabelColor: g.textMuted,
        labelStyle: GhinaType.button,
        unselectedLabelStyle: GhinaType.button,
        indicatorColor: GhinaColors.blue.base,
        dividerColor: g.border,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? GhinaColors.darkSurfaceAlt : GhinaColors.eel,
          borderRadius: GhinaRadii.rMd,
        ),
        textStyle: GhinaType.bodyS.w(700).copyWith(color: Colors.white),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: g.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: GhinaType.body.w(700).copyWith(color: g.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: GhinaRadii.rLg,
          side: BorderSide(color: g.border, width: 2),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: g.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: GhinaColors.green.base,
        headerForegroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: GhinaRadii.rXxl),
        dayStyle: GhinaType.body.w(700),
        todayBorder: BorderSide(color: GhinaColors.green.base, width: 2),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: GhinaColors.green.base,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: GhinaRadii.rXl),
      ),
      // Fallback Material buttons, styled flat-chunky. Prefer ChunkyButton.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GhinaColors.green.base,
          foregroundColor: Colors.white,
          textStyle: GhinaType.button,
          minimumSize: const Size(64, 50),
          shape: const RoundedRectangleBorder(borderRadius: GhinaRadii.rLg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: GhinaColors.green.base,
          foregroundColor: Colors.white,
          textStyle: GhinaType.button,
          minimumSize: const Size(64, 50),
          shape: const RoundedRectangleBorder(borderRadius: GhinaRadii.rLg),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: GhinaColors.blue.base,
          textStyle: GhinaType.button,
          minimumSize: const Size(64, 50),
          side: BorderSide(color: g.border, width: 2),
          shape: const RoundedRectangleBorder(borderRadius: GhinaRadii.rLg),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: GhinaColors.blue.base,
          textStyle: GhinaType.button,
        ),
      ),
    );
  }
}
