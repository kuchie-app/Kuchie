import 'package:material_ui/material_ui.dart';

/// Floating Reader controls sit over manga pages regardless of the app theme.
abstract final class ReaderOverlayColors {
  static const seekBarSurface = Color(0x99000000);
  static const seekBarAccent = Color(0xFFAFC7FF);
  static const chapterPickerGlassTint = Color(0x30000000);
  static const chapterPickerSurface = Color(0xC4000000);
  static const selectedChapterFill = Color(0x23FFFFFF);
  static const chapterPickerButtonSurface = Colors.black54;
  static const pageCounterSurface = Color(0xB8000000);
  static const topBarScrim = <Color>[
    Color(0x80000000),
    Color(0x50000000),
    Colors.transparent,
  ];
}

/// A Reader canvas can have a different brightness than the app theme.
Color readerCanvasForeground(Color canvas) =>
    ThemeData.estimateBrightnessForColor(canvas) == Brightness.dark
    ? Colors.white
    : Colors.black;
