import 'dart:ui';

/// Colors of the Serverpod design system's blue hero picture,
/// `hero-cloud.webp` (indigo to cyan), taken from the `[data-theme="cloud"]`
/// `--hero-*` tokens the design system samples from it. The darkest tones
/// are lifted so the preview backdrop never reads as pure black.
abstract final class PreviewHeroPalette {
  /// `--hero-indigo` (#141B56), lifted.
  static const Color base = Color(0xFF1A2262);

  /// Four corner colors for [AnimatedMeshGradient] (exactly four required).
  static const List<Color> meshColors = [
    // Between `--hero-glow` (#42C4FC) and `--hero-haze` (#B2F5FE): the
    // cyan floor of the picture.
    Color(0xFF7ADCFD),
    // The bright blue band across its middle.
    Color(0xFF3A8AE6),
    // `--hero-mid`.
    Color(0xFF2E46A3),
    base,
  ];
}
