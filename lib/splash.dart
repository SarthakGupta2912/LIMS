import 'dart:math' as math;

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Future<void> Function() initialize;
  final Widget child;
  final Duration minimumDuration;

  const SplashScreen({
    super.key,
    required this.initialize,
    required this.child,
    this.minimumDuration = const Duration(milliseconds: 1700),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _pulseController;
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _start();
  }

  Future<void> _start() async {
    try {
      await Future.wait([
        widget.initialize(),
        Future<void>.delayed(widget.minimumDuration),
      ]);
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _introController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: _ready
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : _error != null
          ? _SplashError(key: const ValueKey('error'), error: _error!)
          : _SplashBody(
              key: const ValueKey('splash'),
              intro: _introController,
              pulse: _pulseController,
            ),
    );
  }
}

class _SplashBody extends StatelessWidget {
  final Animation<double> intro;
  final Animation<double> pulse;

  const _SplashBody({super.key, required this.intro, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF08181C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, _) => CustomPaint(
                painter: _SplashPainter(reduceMotion ? 0 : pulse.value),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: intro,
                builder: (context, child) {
                  final value = reduceMotion
                      ? 1.0
                      : Curves.easeOutCubic.transform(intro.value);
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 24 * (1 - value)),
                      child: Transform.scale(
                        scale: .9 + (.1 * value),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 176,
                        height: 176,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(
                            color: const Color(
                              0xFF7DEBFF,
                            ).withValues(alpha: .3),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/invoice-manager-playstore-icon-1024.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'LIMS',
                        style: TextStyle(
                          color: Color(0xFFF7FBFF),
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Invoices. Inventory. Insight.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .66),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 34),
                      SizedBox(
                        width: 112,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: const LinearProgressIndicator(
                            minHeight: 2,
                            backgroundColor: Color(0xFF18353B),
                            color: Color(0xFF7DEBFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  final double progress;

  const _SplashPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 42);
    final shortestSide = math.min(size.width, size.height);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var index = 0; index < 3; index++) {
      final phase = (progress + (index / 3)) % 1;
      linePaint.color = const Color(
        0xFF7DEBFF,
      ).withValues(alpha: .12 * (1 - phase));
      canvas.drawCircle(center, shortestSide * (.2 + (.34 * phase)), linePaint);
    }

    linePaint.color = Colors.white.withValues(alpha: .035);
    final spacing = shortestSide < 500 ? 44.0 : 58.0;
    for (double x = center.dx % spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = center.dy % spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(_SplashPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _SplashError extends StatelessWidget {
  final Object error;

  const _SplashError({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08181C),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.storage_rounded,
                color: Color(0xFFFFB4AB),
                size: 40,
              ),
              const SizedBox(height: 18),
              const Text(
                'Could not open local database',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFF7FBFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .62),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
