import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Lightweight 3D vector with Euler rotations and vector products.
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 normalized() {
    final len = length;
    if (len < 1e-9) return const Vec3(0, 0, 1);
    return Vec3(x / len, y / len, z / len);
  }

  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  Vec3 cross(Vec3 other) => Vec3(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );

  Vec3 rotateX(double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Vec3(x, y * c - z * s, y * s + z * c);
  }

  Vec3 rotateY(double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Vec3(x * c + z * s, y, -x * s + z * c);
  }

  Vec3 rotateZ(double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Vec3(x * c - y * s, x * s + y * c, z);
  }
}

/// Projects a 3D point into 2D canvas coordinates with perspective foreshortening.
Offset project3D(
  Vec3 v,
  Size size, {
  double fov = 260,
  double distance = 4.2,
}) {
  final denom = (distance - v.z).clamp(0.6, 20.0);
  final perspective = fov / denom;
  return Offset(
    size.width * 0.5 + v.x * perspective,
    size.height * 0.5 + v.y * perspective,
  );
}

/// Depth-sorted projected quad representing one face of a 3D cube.
class ProjectedCubeFace {
  final int faceIndex;
  final List<Offset> points;
  final double avgZ;
  final double light;
  final double normalZ;

  const ProjectedCubeFace({
    required this.faceIndex,
    required this.points,
    required this.avgZ,
    required this.light,
    required this.normalZ,
  });
}

const List<Vec3> _kCubeVertices = [
  Vec3(-1, -1, -1),
  Vec3(1, -1, -1),
  Vec3(1, 1, -1),
  Vec3(-1, 1, -1),
  Vec3(-1, -1, 1),
  Vec3(1, -1, 1),
  Vec3(1, 1, 1),
  Vec3(-1, 1, 1),
];

const List<List<int>> _kCubeFaces = [
  [4, 5, 6, 7],
  [1, 0, 3, 2],
  [5, 1, 2, 6],
  [0, 4, 7, 3],
  [3, 2, 6, 7],
  [0, 1, 5, 4],
];

/// Rotates unit cube vertices, computes directional lighting, and returns all 6
/// faces sorted back-to-front by average Z depth (Painter's algorithm).
List<ProjectedCubeFace> computeCubeFaces(
  double rotX,
  double rotY,
  double rotZ,
  Size size, {
  double scale = 1.0,
}) {
  final fov = math.min(size.width, size.height) * 1.38 * scale;
  final lightDir = const Vec3(-0.45, -0.65, 0.85).normalized();

  final transformed = _kCubeVertices
      .map((v) => v.rotateX(rotX).rotateY(rotY).rotateZ(rotZ))
      .toList(growable: false);
  final projected = transformed
      .map((v) => project3D(v, size, fov: fov))
      .toList(growable: false);

  final out = <ProjectedCubeFace>[];
  for (var i = 0; i < _kCubeFaces.length; i++) {
    final idx = _kCubeFaces[i];
    final v0 = transformed[idx[0]];
    final v1 = transformed[idx[1]];
    final v2 = transformed[idx[2]];
    final v3 = transformed[idx[3]];

    final avgZ = (v0.z + v1.z + v2.z + v3.z) * 0.25;
    final normal = (v1 - v0).cross(v2 - v0).normalized();
    final diffuse = ((normal.dot(lightDir) + 1.0) * 0.5).clamp(0.0, 1.0);
    final light = (0.28 + 0.72 * diffuse).clamp(0.0, 1.0);

    out.add(
      ProjectedCubeFace(
        faceIndex: i,
        points: [
          projected[idx[0]],
          projected[idx[1]],
          projected[idx[2]],
          projected[idx[3]],
        ],
        avgZ: avgZ,
        light: light,
        normalZ: normal.z,
      ),
    );
  }

  out.sort((a, b) => a.avgZ.compareTo(b.avgZ));
  return out;
}

/// Hisobchi — yuklanish (splash) ekrani.
/// Silliq radial yorug'lik, 3D egilgan binafsha kub-ikonka, 12 yaproqli burst va pastki yoy.
class HisobchiSplash extends StatefulWidget {
  const HisobchiSplash({
    super.key,
    this.onFinished,
    this.duration = const Duration(seconds: 3),
    this.title = 'Hisobchi',
    this.subtitle = 'Ilova tayyorlanmoqda...',
  });

  final VoidCallback? onFinished;
  final Duration duration;
  final String title;
  final String subtitle;

  @override
  State<HisobchiSplash> createState() => _HisobchiSplashState();
}

class _HisobchiSplashState extends State<HisobchiSplash>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);
  late final AnimationController _bar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    if (widget.onFinished != null) {
      _finishTimer = Timer(widget.duration, () {
        if (mounted) widget.onFinished!();
      });
    }
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _spin.dispose();
    _orbit.dispose();
    _pulse.dispose();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05030F),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _BottomArcPainter(_pulse)),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIcon(),
                    const SizedBox(height: 36),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _buildBar(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    return SizedBox(
      width: 300,
      height: 300,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _orbit, _pulse]),
        builder: (context, _) {
          final p = Curves.easeInOut.transform(_pulse.value);
          final tiltX = -0.30 + 0.06 * math.sin(_orbit.value * 2 * math.pi);
          final tiltY = 0.35 + 0.08 * math.cos(_orbit.value * 2 * math.pi);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFB44CFF).withValues(alpha: 0.30 + 0.20 * p),
                      const Color(0xFF7C3AED).withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(300, 300),
                painter: _OrbitPainter(_orbit.value),
              ),
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(tiltX)
                  ..rotateY(tiltY)
                  ..rotateZ(-0.12),
                child: _buildGlossyTile(size: 164, pulse: p, spin: _spin.value),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBar() {
    return SizedBox(
      width: 230,
      height: 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.08)),
            AnimatedBuilder(
              animation: _bar,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_bar.value);
                return Align(
                  alignment: Alignment(-1 + 2 * t, 0),
                  child: FractionallySizedBox(
                    widthFactor: 0.38,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFA855F7),
                            Color(0xFFFF7ACB),
                            Colors.white,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFA855F7).withValues(alpha: 0.7),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildGlossyTile({
  required double size,
  required double pulse,
  required double spin,
}) {
  final scale = size / 164.0;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(44 * scale),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE0A8FF),
          Color(0xFFA855F7),
          Color(0xFF5B21B6),
          Color(0xFFC026D3),
        ],
        stops: [0.0, 0.35, 0.75, 1.0],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFB44CFF).withValues(alpha: 0.45 + 0.25 * pulse),
          blurRadius: (50 + 20 * pulse) * scale,
          spreadRadius: 2 * scale,
        ),
        BoxShadow(
          color: const Color(0xFFFF4FD8).withValues(alpha: 0.18),
          blurRadius: 90 * scale,
          spreadRadius: 6 * scale,
        ),
      ],
    ),
    padding: EdgeInsets.all(11 * scale),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34 * scale),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1030), Color(0xFF07040F)],
        ),
      ),
      child: CustomPaint(painter: _BurstPainter(spin)),
    ),
  );
}

/// Interactive 3D emblem matching [HisobchiSplash] (used on LoginScreen hero).
class Interactive3DFintechCube extends StatefulWidget {
  final double size;
  final VoidCallback? onInteractStart;
  final VoidCallback? onInteractEnd;
  final bool interactive;
  final bool continuousSpin;

  const Interactive3DFintechCube({
    super.key,
    this.size = 188,
    this.onInteractStart,
    this.onInteractEnd,
    this.interactive = true,
    this.continuousSpin = true,
  });

  @override
  State<Interactive3DFintechCube> createState() =>
      _Interactive3DFintechCubeState();
}

class _Interactive3DFintechCubeState extends State<Interactive3DFintechCube>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _tiltX = -0.26;
  double _tiltY = 0.32;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  double _velX = 0.0;
  double _velY = 0.0;
  double _phase = 0.0;
  double _spin = 0.0;
  double _pulse = 0.35;
  double _introRemaining = 0.0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    if (!widget.continuousSpin) {
      _introRemaining = 1.05;
      _offsetY = -0.35;
      _offsetX = 0.16;
      _velY = 1.05;
      _velX = -0.45;
    }
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTickerState();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickerState();
  }

  void _syncTickerState() {
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final ticker = _ticker;
    if (ticker == null) return;
    if (disabled) {
      ticker.stop();
      return;
    }
    final needsRun = widget.continuousSpin ||
        _dragging ||
        _introRemaining > 0 ||
        _velX.abs() > 0.012 ||
        _velY.abs() > 0.012;
    if (needsRun && !ticker.isActive) {
      _lastTick = Duration.zero;
      ticker.start();
    } else if (!needsRun && ticker.isActive) {
      ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dtRaw = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final dt = dtRaw.clamp(0.001, 0.05);

    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _ticker?.stop();
      return;
    }

    setState(() {
      _phase += dt;
      _spin = (_spin + dt / 1.4) % 1.0;
      _pulse = 0.5 - 0.5 * math.cos(_phase * 2.2);
      if (_introRemaining > 0) {
        _introRemaining = math.max(0.0, _introRemaining - dt);
      }
      if (!_dragging) {
        _offsetY += _velY * dt;
        _offsetX += _velX * dt;
        final damping = math.pow(0.05, dt).toDouble();
        _velX *= damping;
        _velY *= damping;
        _offsetX *= (1.0 - (dt * 2.2).clamp(0.0, 0.25));
        _offsetY *= (1.0 - (dt * 2.2).clamp(0.0, 0.25));
        if (_velX.abs() < 0.012) _velX = 0.0;
        if (_velY.abs() < 0.012) _velY = 0.0;
      }
      final floatX =
          widget.continuousSpin ? 0.06 * math.sin(_phase * 0.7) : 0.0;
      final floatY =
          widget.continuousSpin ? 0.08 * math.cos(_phase * 0.7) : 0.0;
      _tiltX = (-0.28 + floatX + _offsetX).clamp(-0.95, 0.95);
      _tiltY = (0.34 + floatY + _offsetY).clamp(-1.1, 1.1);
    });

    if (!widget.continuousSpin &&
        !_dragging &&
        _introRemaining <= 0 &&
        _velX == 0.0 &&
        _velY == 0.0) {
      _ticker?.stop();
    }
  }

  void _handlePanStart(DragStartDetails _) {
    if (!widget.interactive) return;
    setState(() {
      _dragging = true;
      _velX = 0.0;
      _velY = 0.0;
    });
    widget.onInteractStart?.call();
    _syncTickerState();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!widget.interactive) return;
    setState(() {
      _offsetY = (_offsetY + details.delta.dx * 0.01).clamp(-0.85, 0.85);
      _offsetX = (_offsetX - details.delta.dy * 0.01).clamp(-0.75, 0.75);
      _velY = (details.delta.dx * 0.35).clamp(-6.5, 6.5);
      _velX = (-details.delta.dy * 0.35).clamp(-6.5, 6.5);
      _tiltX = (-0.28 + _offsetX).clamp(-0.95, 0.95);
      _tiltY = (0.34 + _offsetY).clamp(-1.1, 1.1);
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!widget.interactive) return;
    final pps = details.velocity.pixelsPerSecond;
    setState(() {
      _dragging = false;
      _velY = (pps.dx * 0.003).clamp(-6.5, 6.5);
      _velX = (-pps.dy * 0.003).clamp(-6.5, 6.5);
    });
    widget.onInteractEnd?.call();
    _syncTickerState();
  }

  void _handleTap() {
    if (!widget.interactive) return;
    HapticFeedback.lightImpact();
    widget.onInteractStart?.call();
    setState(() {
      _velY += 2.6;
      _velX -= 1.0;
    });
    _syncTickerState();
    widget.onInteractEnd?.call();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tileSize = widget.size * 0.55;
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: widget.interactive ? _handlePanStart : null,
        onPanUpdate: widget.interactive ? _handlePanUpdate : null,
        onPanEnd: widget.interactive ? _handlePanEnd : null,
        onTap: widget.interactive ? _handleTap : null,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * 0.94,
                height: widget.size * 0.94,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFB44CFF)
                          .withValues(alpha: 0.28 + 0.16 * _pulse),
                      const Color(0xFF7C3AED).withValues(alpha: 0.09),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _OrbitPainter((_phase / 9.0) % 1.0),
              ),
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(_tiltX)
                  ..rotateY(_tiltY)
                  ..rotateZ(-0.12),
                child: _buildGlossyTile(
                  size: tileSize,
                  pulse: _pulse,
                  spin: _spin,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper keeping the welcome screen API backed by [HisobchiSplash].
class Hisobchi3DWelcomeScreen extends StatelessWidget {
  final VoidCallback onContinue;
  final String title;
  final String subtitle;
  final Duration autoContinueDelay;

  const Hisobchi3DWelcomeScreen({
    super.key,
    required this.onContinue,
    this.title = 'Hisobchi',
    this.subtitle = 'Ilova tayyorlanmoqda...',
    this.autoContinueDelay = const Duration(seconds: 3),
  });

  @override
  Widget build(BuildContext context) {
    return HisobchiSplash(
      title: title,
      subtitle: subtitle,
      duration: autoContinueDelay,
      onFinished: onContinue,
    );
  }
}

/// 12 ta yaproqli aylanuvchi "burst" (rasmdagi markaziy belgi).
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r1 = size.width * 0.36;
    final r0 = size.width * 0.15;
    const n = 12;
    const step = 2 * math.pi / n;
    const gap = 0.16;

    for (int i = 0; i < n; i++) {
      final a0 = i * step + gap / 2 - math.pi / 2;
      final sweep = step - gap;
      final a1 = a0 + sweep;

      final path = Path()
        ..moveTo(c.dx + math.cos(a0) * r0, c.dy + math.sin(a0) * r0)
        ..lineTo(c.dx + math.cos(a0) * r1, c.dy + math.sin(a0) * r1)
        ..arcTo(Rect.fromCircle(center: c, radius: r1), a0, sweep, false)
        ..lineTo(c.dx + math.cos(a1) * r0, c.dy + math.sin(a1) * r0)
        ..arcTo(Rect.fromCircle(center: c, radius: r0), a1, -sweep, false)
        ..close();

      final k = ((i / n) - t) % 1.0;
      final bright = math.pow(k < 0 ? k + 1 : k, 1.6).toDouble();
      final color = Color.lerp(
        const Color(0xFF9B3FA8),
        Colors.white,
        bright,
      )!
          .withValues(alpha: 0.35 + 0.65 * bright);

      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.45 * bright)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.t != t;
}

/// Ikonka atrofidagi qiya orbita halqalari va nuqtalar.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final s = size.width / 300.0;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.16);

    void orbit(double w, double h, double rot, double phase, double speed) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(rot);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: w * s, height: h * s),
        ring,
      );
      final a = (t * speed + phase) * 2 * math.pi;
      final dot = Offset(
        math.cos(a) * (w * s) / 2,
        math.sin(a) * (h * s) / 2,
      );
      canvas.drawCircle(
        dot,
        5 * s,
        Paint()
          ..color = const Color(0xFFFF9BE5).withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(dot, 2.4 * s, Paint()..color = Colors.white);
      canvas.restore();
    }

    orbit(285, 215, -0.35, 0.10, 1);
    orbit(255, 175, 0.55, 0.60, -1);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.t != t;
}

/// Ekran pastidagi yorqin binafsha yoy.
class _BottomArcPainter extends CustomPainter {
  _BottomArcPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Curves.easeInOut.transform(anim.value);
    final rect = Rect.fromCenter(
      center: Offset(w / 2, size.height + w * 0.36),
      width: w * 1.7,
      height: w * 0.92,
    );

    canvas.drawOval(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF8B2FE0).withValues(alpha: 0.35 + 0.15 * p),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFFD27BFF).withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFF0C8FF).withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _BottomArcPainter old) => false;
}
