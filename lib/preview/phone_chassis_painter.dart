import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'preview_device.dart';

/// Paints the body of the generic phone around the preview: a drop shadow, a
/// metal outer rim, a dark grey band, the black inner frame, and the side
/// buttons with a beveled edge.
///
/// The body sits inside the frame box by [previewPhoneHardwareOverhang] on
/// every side. Its geometry does not depend on orientation; only the buttons
/// turn with the device, so in landscape they move to the top and bottom edges
/// the way they would on a phone turned on its side.
class PhoneChassisPainter extends CustomPainter {
  const PhoneChassisPainter({required this.landscape, required this.dark});

  /// Whether the device is turned on its side.
  final bool landscape;

  /// Whether the app shell is dark. Only the shadow changes with it: the
  /// device itself is the same graphite in both.
  final bool dark;

  // Outside in: thin black outline, metal rim, dark grey line, black frame.
  static const _outline = Color(0xFF000000);
  static const _metalLight = Color(0xFFB4B4BA);
  static const _metalMid = Color(0xFF6E6E74);
  static const _metalDark = Color(0xFF8A8A90);
  static const _grey = Color(0xFF2E2E32);
  static const _bezel = Color(0xFF060607);

  static const _bevelLight = Color(0x66FFFFFF);
  static const _bevelShade = Color(0x73000000);

  static const _outlineWidth = 1.2;
  static const _metalWidth = 1.2;
  // The black frame is the rest of the bezel; the grey line is a third of it.
  static const _greyWidth =
      (previewPhoneBezel - _outlineWidth - _metalWidth) / 4;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTWH(
      previewPhoneHardwareOverhang,
      previewPhoneHardwareOverhang,
      size.width - previewPhoneHardwareOverhang * 2,
      size.height - previewPhoneHardwareOverhang * 2,
    );
    final bodyRadius = Radius.circular(previewPhoneOuterCornerRadius);
    final bodyRRect = RRect.fromRectAndRadius(body, bodyRadius);

    _paintShadow(canvas, bodyRRect);

    // The buttons go under the body, so they appear to come out from behind
    // its edge and never paint across the metal rim.
    _paintButtons(canvas, size);

    // Each layer is the one outside it inset by its width, so the rings stack
    // from the outline inward: black outline, metal, grey line, black frame.
    canvas.drawRRect(bodyRRect, Paint()..color = _outline);
    final metalRRect = bodyRRect.deflate(_outlineWidth);
    canvas.drawRRect(
      metalRRect,
      Paint()
        ..shader = ui.Gradient.linear(
          body.topLeft,
          body.bottomRight,
          const [_metalLight, _metalMid, _metalDark],
          const [0.0, 0.55, 1.0],
        ),
    );
    final greyRRect = metalRRect.deflate(_metalWidth);
    canvas.drawRRect(greyRRect, Paint()..color = _grey);
    canvas.drawRRect(greyRRect.deflate(_greyWidth), Paint()..color = _bezel);
  }

  void _paintShadow(Canvas canvas, RRect body) {
    final alpha = dark ? 0.75 : 0.45;
    // The wide shadow sits low, like light from above; the tight one hugs the
    // edge so the device still reads against a light backdrop.
    canvas.drawRRect(
      body.shift(const Offset(0, 10)),
      Paint()
        ..color = Colors.black.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      body.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  /// Buttons are laid out on the portrait device and then turned into place.
  void _paintButtons(Canvas canvas, Size size) {
    final portrait = landscape ? Size(size.height, size.width) : size;
    final buttons = _buttonRects(portrait);

    canvas.save();
    if (landscape) {
      // Maps portrait (u, v) to landscape (width - v, u): the left edge becomes
      // the top edge, as on a phone turned clockwise.
      canvas.translate(size.width, 0);
      canvas.rotate(math.pi / 2);
    }
    for (final rect in buttons) {
      final button = RRect.fromRectAndRadius(rect, const Radius.circular(1.5));
      // Body of the button: lit from above, darker toward the bottom.
      canvas.drawRRect(
        button,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            const [_metalLight, _metalMid, _metalDark],
            const [0.0, 0.55, 1.0],
          ),
      );
      // Bevel: light along the top, shade along the bottom, inside the outline.
      canvas.drawRRect(
        button.deflate(0.9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            const [_bevelLight, Color(0x00FFFFFF), _bevelShade],
            const [0.0, 0.5, 1.0],
          ),
      );
      // Thin black outline, as the frame has.
      canvas.drawRRect(
        button.deflate(0.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = _outline,
      );
    }
    canvas.restore();
  }

  /// Portrait positions: volume and action on the left, power on the right.
  /// Each rect runs from the outer frame edge to a point just inside the body,
  /// so it looks attached rather than floating.
  List<Rect> _buttonRects(Size portrait) {
    const o = previewPhoneHardwareOverhang;
    final bodyTop = o;
    final bodyHeight = portrait.height - o * 2;
    // Reaches two points past the body edge, under the metal, so no seam shows.
    final attach = o + 2;

    Rect left(double top, double height) => Rect.fromLTRB(
      0,
      bodyTop + bodyHeight * top,
      attach,
      bodyTop + bodyHeight * (top + height),
    );
    Rect right(double top, double height) => Rect.fromLTRB(
      portrait.width - attach,
      bodyTop + bodyHeight * top,
      portrait.width,
      bodyTop + bodyHeight * (top + height),
    );

    return [
      left(0.14, 0.05), // action (silent) switch
      left(0.21, 0.09), // volume up
      left(0.31, 0.09), // volume down
      right(0.24, 0.14), // side button
    ];
  }

  @override
  bool shouldRepaint(PhoneChassisPainter oldDelegate) =>
      oldDelegate.landscape != landscape || oldDelegate.dark != dark;
}
