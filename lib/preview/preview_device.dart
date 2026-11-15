import 'dart:ui';

/// Common phone logical viewport (CSS px) — iPhone 14/15 class devices.
const previewPhonePortraitWidth = 390.0;
const previewPhonePortraitHeight = 844.0;

enum PreviewDisplayMode { desktop, phone }

enum PreviewOrientation { portrait, landscape }

enum PreviewViewMode { phonePortrait, phoneLandscape, desktop }

extension PreviewViewModeX on PreviewViewMode {
  PreviewDisplayMode get displayMode => switch (this) {
    PreviewViewMode.desktop => PreviewDisplayMode.desktop,
    PreviewViewMode.phonePortrait ||
    PreviewViewMode.phoneLandscape => PreviewDisplayMode.phone,
  };

  PreviewOrientation get orientation => switch (this) {
    PreviewViewMode.phoneLandscape => PreviewOrientation.landscape,
    PreviewViewMode.desktop ||
    PreviewViewMode.phonePortrait => PreviewOrientation.portrait,
  };
}

Size previewPhoneViewport(PreviewOrientation orientation) {
  return switch (orientation) {
    PreviewOrientation.portrait => const Size(
      previewPhonePortraitWidth,
      previewPhonePortraitHeight,
    ),
    PreviewOrientation.landscape => const Size(
      previewPhonePortraitHeight,
      previewPhonePortraitWidth,
    ),
  };
}

/// Outer frame size: the viewport plus the bezel and the hardware overhang on
/// every side. The overhang is symmetric so the frame's box is the same in
/// both orientations; only the buttons on it turn with the device.
Size previewPhoneFrameSize(PreviewOrientation orientation) {
  const edge = (previewPhoneBezel + previewPhoneHardwareOverhang) * 2;
  final viewport = previewPhoneViewport(orientation);
  return Size(viewport.width + edge, viewport.height + edge);
}

/// Black glass between the screen and the metal edge.
const previewPhoneBezel = 10.0;

/// How far the side buttons stand proud of the body. The frame box includes
/// it, so the buttons are drawn inside the window's own bounds.
const previewPhoneHardwareOverhang = 3.0;

/// Screen corner radius (inner clip).
const previewPhoneCornerRadius = 36.0;

/// Outer body radius — [previewPhoneCornerRadius] + [previewPhoneBezel], so
/// the bezel is an even width around the corners.
const previewPhoneOuterCornerRadius =
    previewPhoneCornerRadius + previewPhoneBezel;
const previewPhonePreviewPadding = 16.0;
