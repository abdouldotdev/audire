import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'design_system.dart';

const onboardingArtwork = 'assets/onboarding-landscape.png';

/// A fixed composition scales as one illustration. Its outer box always takes
/// the available width, so positioned details cannot collapse behind the book.
class OnboardingBookScene extends StatelessWidget {
  const OnboardingBookScene({super.key, required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: RepaintBoundary(
          child: SizedBox(
            width: double.infinity,
            child: AspectRatio(
              aspectRatio: 1.22,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 360,
                  height: 295,
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      final phase = animation.value * math.pi * 2;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 44,
                            top: 8,
                            width: 268,
                            height: 268,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    p.accent.withValues(alpha: .13),
                                    p.accent.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 168,
                            top: 43 + math.sin(phase + 1) * 3,
                            child: Transform.rotate(
                              angle: .13,
                              child: Container(
                                width: 160,
                                height: 206,
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  26,
                                  18,
                                  18,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0EBDE),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .13,
                                      ),
                                      blurRadius: 22,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'LE PREMIER JOUR',
                                      style: TextStyle(
                                        color: Color(0xFF707569),
                                        fontSize: 7,
                                        letterSpacing: 1.3,
                                      ),
                                    ),
                                    SizedBox(height: 14),
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.topLeft,
                                        child: Text(
                                          'Il suffisait\nd’ouvrir un livre\npour être\nailleurs.',
                                          style: TextStyle(
                                            color: Color(0xFF34473A),
                                            fontFamily: LisiereTheme.serif,
                                            fontSize: 17,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '—  01  —',
                                      style: TextStyle(
                                        color: Color(0xFF777D72),
                                        fontSize: 8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 45,
                            top: 16 + math.sin(phase) * 4,
                            child: Transform.rotate(
                              angle: -.09 + math.sin(phase) * .008,
                              child: Container(
                                width: 186,
                                height: 254,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .28,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(3, 16),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.asset(
                                        onboardingArtwork,
                                        fit: BoxFit.cover,
                                        cacheWidth: 600,
                                      ),
                                      const Positioned(
                                        left: 23,
                                        right: 16,
                                        top: 22,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'LES HEURES',
                                              style: TextStyle(
                                                fontFamily: LisiereTheme.serif,
                                                fontSize: 24,
                                                color: Color(0xFFF6EBD1),
                                              ),
                                            ),
                                            Text(
                                              'suspendues',
                                              style: TextStyle(
                                                fontFamily: LisiereTheme.serif,
                                                fontStyle: FontStyle.italic,
                                                fontSize: 25,
                                                color: Color(0xFFF6EBD1),
                                              ),
                                            ),
                                            SizedBox(height: 9),
                                            Text(
                                              'UNE INVITATION AU VOYAGE',
                                              style: TextStyle(
                                                fontSize: 5.5,
                                                letterSpacing: 1.6,
                                                color: Color(0xFFE7D7AF),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 15,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.black.withValues(
                                                  alpha: .35,
                                                ),
                                                Colors.white.withValues(
                                                  alpha: .10,
                                                ),
                                                Colors.transparent,
                                              ],
                                              stops: const [0, .4, 1],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 252,
                            top: 228,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: p.surface,
                                border: Border.all(color: p.line),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: OnboardingWaveform(
                                animation: animation,
                                color: p.accent,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingWaveform extends StatelessWidget {
  const OnboardingWaveform({
    super.key,
    required this.animation,
    required this.color,
  });
  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: AnimatedBuilder(
      animation: animation,
      builder:
          (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              9,
              (i) => Container(
                width: 2.5,
                height:
                    5 +
                    (math.sin(animation.value * math.pi * 4 + i * .8) + 1) * 8,
                margin: const EdgeInsets.symmetric(horizontal: 1.6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
    ),
  );
}

class OnboardingLandscapeBanner extends StatelessWidget {
  const OnboardingLandscapeBanner({
    super.key,
    required this.child,
    this.height = 144,
  });
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            onboardingArtwork,
            fit: BoxFit.cover,
            alignment: const Alignment(0, .25),
            cacheWidth: 900,
          ),
          ColoredBox(color: const Color(0xFF102D20).withValues(alpha: .45)),
          Padding(padding: const EdgeInsets.all(22), child: child),
        ],
      ),
    ),
  );
}
