import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary (Amber)
  static const primary = Color(0xFFB26A00);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFFFA726);
  static const onPrimaryContainer = Color(0xFF5C3500);
  static const primaryFixed = Color(0xFFFFDDB0);
  static const primaryFixedDim = Color(0xFFFFC078);

  // Secondary (Slate Blue)
  static const secondary = Color(0xFF4A5C70);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFD6E3F2);
  static const onSecondaryContainer = Color(0xFF2E3B49);

  // Error
  static const error = Color(0xFFC62828);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF8B0000);

  // Surface & Neutral
  static const background = Color(0xFFFFFBF5);
  static const surface = Color(0xFFFFFBF5);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFFFF4E6);
  static const surfaceContainer = Color(0xFFFBEBD8);
  static const surfaceContainerHigh = Color(0xFFF5E2D0);
  static const surfaceContainerHighest = Color(0xFFEFDAC4);
  static const surfaceVariant = Color(0xFFEFDFCB);
  static const onSurface = Color(0xFF1F1810);
  static const onSurfaceVariant = Color(0xFF564738);
  static const outline = Color(0xFF877462);
  static const outlineVariant = Color(0xFFD7C3AE);
}

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color pending;
  final Color info;
  final Color warning;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.pending,
    required this.info,
    required this.warning,
  });

  static const light = AppSemanticColors(
    success: Color(0xFF2E7D32),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFC8E6C9),
    onSuccessContainer: Color(0xFF1B5E20),
    pending: Color(0xFF877462),
    info: Color(0xFF4A5C70),
    warning: Color(0xFFED6C02),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? pending,
    Color? info,
    Color? warning,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      pending: pending ?? this.pending,
      info: info ?? this.info,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) => this;
}

extension SemanticColorsX on BuildContext {
  AppSemanticColors get semanticColors => Theme.of(this).extension<AppSemanticColors>()!;
}
