import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/glass.dart';

/// A translucent panel.
///
/// When [lit] it brightens, takes an accent edge-light down its leading side,
/// and catches a slow specular sweep. That difference is the answer to the only
/// question this app exists to answer: which identity am I right now.
class GlassSlab extends StatefulWidget {
  const GlassSlab({
    super.key,
    required this.child,
    this.lit = false,
    this.accent,
    this.padding = const EdgeInsets.all(Glass.slabPadding),
  });

  final Widget child;
  final bool lit;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  @override
  State<GlassSlab> createState() => _GlassSlabState();
}

class _GlassSlabState extends State<GlassSlab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void initState() {
    super.initState();
    if (widget.lit) _sheen.repeat();
  }

  @override
  void didUpdateWidget(GlassSlab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lit && !_sheen.isAnimating) {
      _sheen.repeat();
    } else if (!widget.lit && _sheen.isAnimating) {
      _sheen.stop();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? Glass.accents.first;
    // The sweep is ambient decoration, so it is the first thing to go when the
    // system asks for less motion.
    final allowMotion = !MediaQuery.disableAnimationsOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(Glass.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Glass.slabFill(context, lit: widget.lit),
            borderRadius: BorderRadius.circular(Glass.radius),
            border: Border.all(
              color: Glass.slabStroke(context, lit: widget.lit),
              width: 0.8,
            ),
            boxShadow: widget.lit
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.22),
                      blurRadius: 26,
                      spreadRadius: -6,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              if (widget.lit && allowMotion)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _sheen,
                      builder: (context, _) => CustomPaint(
                        painter: _SheenPainter(_sheen.value),
                      ),
                    ),
                  ),
                ),
              if (widget.lit)
                Positioned(
                  left: 0,
                  top: 12,
                  bottom: 12,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accent.withValues(alpha: 0.25),
                          accent,
                          accent.withValues(alpha: 0.25),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              Padding(padding: widget.padding, child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single highlight travelling across the slab, the way light crosses glass.
class _SheenPainter extends CustomPainter {
  const _SheenPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Most of the cycle is dark: the sweep should read as an occasional
    // glint, not a pulsing gradient.
    final position = progress * 2.2 - 0.6;
    if (position < -0.35 || position > 1.35) return;

    final band = size.width * 0.42;
    final centre = size.width * position;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromLTWH(centre - band / 2, 0, band, size.height),
      );

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_SheenPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
