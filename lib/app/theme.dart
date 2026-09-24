import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const _seed = Color(0xFF1D3F8F);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [
        brightness == Brightness.light ? StatusColors.light : StatusColors.dark,
      ],
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Danger / warning / success colours. Always shown together with an icon
/// and text, never colour alone (Accessibility NFR).
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.danger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  static const light = StatusColors(
    danger: Color(0xFFB3261E),
    dangerContainer: Color(0xFFFFDAD6),
    onDangerContainer: Color(0xFF410002),
    warning: Color(0xFF8A5100),
    warningContainer: Color(0xFFFFDDB3),
    onWarningContainer: Color(0xFF2B1700),
    success: Color(0xFF1B6D2F),
    successContainer: Color(0xFFB7F1BC),
    onSuccessContainer: Color(0xFF002107),
  );

  static const dark = StatusColors(
    danger: Color(0xFFFFB4AB),
    dangerContainer: Color(0xFF93000A),
    onDangerContainer: Color(0xFFFFDAD6),
    warning: Color(0xFFFFB95C),
    warningContainer: Color(0xFF693C00),
    onWarningContainer: Color(0xFFFFDDB3),
    success: Color(0xFF9CD5A1),
    successContainer: Color(0xFF00531C),
    onSuccessContainer: Color(0xFFB7F1BC),
  );

  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  StatusColors copyWith({
    Color? danger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
  }) {
    return StatusColors(
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer:
          Color.lerp(onDangerContainer, other.onDangerContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
    );
  }
}

/// The three tones used by chips and banners.
enum Tone { danger, warning, success, neutral }

extension ToneColors on Tone {
  (Color background, Color foreground) colors(BuildContext context) {
    final s = StatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return switch (this) {
      Tone.danger => (s.dangerContainer, s.onDangerContainer),
      Tone.warning => (s.warningContainer, s.onWarningContainer),
      Tone.success => (s.successContainer, s.onSuccessContainer),
      Tone.neutral => (scheme.surfaceContainerHighest, scheme.onSurface),
    };
  }
}
