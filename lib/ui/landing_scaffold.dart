import 'package:flutter/material.dart';
import 'package:shad/shad.dart';

import '../theme/app_theme.dart';

const _kBannerHeight = 56.0;
const _kLogoAsset = 'assets/logo-horizontal.webp';

/// The branded chrome every pre-project screen shares: the logo banner above
/// the gradient, with [child] laid over the gradient.
///
/// Shared rather than duplicated because first-run setup and the start page are
/// two states of the same moment — the app open with no project — and giving
/// them different backdrops made moving between them look like a different app.
///
/// [child] is given [buildLandingTheme] rather than the app's, so these screens
/// look the same in light mode as in dark — the backdrop is one fixed image
/// either way.
class LandingScaffold extends StatelessWidget {
  const LandingScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LandingBanner(),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _LandingBackground(),
              ShadTheme(data: buildLandingTheme(), child: child),
            ],
          ),
        ),
      ],
    );
  }
}

class _LandingBanner extends StatelessWidget {
  const _LandingBanner();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // Brand chrome, identical in both themes, so this one is not a token.
      color: Colors.black,
      child: SizedBox(
        height: _kBannerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              _kLogoAsset,
              height: 28,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}

/// The brand backdrop: the Serverpod design system's *action gradient*, near
/// black at the banner deepening through indigo into blue at the floor.
///
/// The design system has two hero backgrounds. The hero picture
/// (`hero-cloud.webp`, indigo to a cyan glow) is for heroes with a feature
/// image and is never to be recreated in code; heroes without one — which is
/// what every landing screen here is — use this gradient. It is the same on
/// every Serverpod product page, so the app's first screen matches the site it
/// was downloaded from.
///
/// The six stops are the design system's `action-gradient-0` … `-100` tokens,
/// placed on even fifths, which is what lets `stops` be omitted. White text
/// holds at least 5.8:1 anywhere on it.
///
/// Drawn rather than loaded: a gradient fills whatever it is given, where an
/// image would have to be decoded, rescaled and letterboxed on every resize.
class _LandingBackground extends StatelessWidget {
  const _LandingBackground();

  static const _gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF000009),
      Color(0xFF020520),
      Color(0xFF0C1043),
      Color(0xFF1A236C),
      Color(0xFF2A3D96),
      Color(0xFF3761BE),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(decoration: BoxDecoration(gradient: _gradient));
  }
}
