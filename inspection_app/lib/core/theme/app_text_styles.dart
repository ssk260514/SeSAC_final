import 'package:flutter/material.dart';

class AppTextStyles {
  AppTextStyles._();

  static const _fontFamily = 'Pretendard';
  static const _tabularNums = FontFeature.tabularFigures();

  static const display = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    height: 36 / 28,
    letterSpacing: -0.56,
    fontWeight: FontWeight.w700,
  );

  static const h1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    height: 32 / 24,
    letterSpacing: -0.48,
    fontWeight: FontWeight.w700,
  );

  static const h2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    height: 28 / 20,
    letterSpacing: -0.20,
    fontWeight: FontWeight.w600,
  );

  static const h3 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    height: 26 / 18,
    letterSpacing: -0.18,
    fontWeight: FontWeight.w600,
  );

  static const bodyLg = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  static const bodyMd = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  static const labelBold = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.12,
    fontWeight: FontWeight.w600,
  );

  static const caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    height: 14 / 11,
    letterSpacing: 0.22,
    fontWeight: FontWeight.w400,
  );

  static const codeData = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0.70,
    fontWeight: FontWeight.w500,
    fontFeatures: [_tabularNums],
  );
}
