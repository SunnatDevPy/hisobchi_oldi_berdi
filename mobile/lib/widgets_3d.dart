import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

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

/// Depth-sorted projected quad representing one face of the 3D cube.
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
  Vec3(-1, -1, -1), // 0
  Vec3(1, -1, -1), // 1
  Vec3(1, 1, -1), // 2
  Vec3(-1, 1, -1), // 3
  Vec3(-1, -1, 1), // 4
  Vec3(1, -1, 1), // 5
  Vec3(1, 1, 1), // 6
  Vec3(-1, 1, 1), // 7
];

const List<List<int>> _kCubeFaces = [
  [4, 5, 6, 7], // front (+Z)
  [1, 0, 3, 2], // back (-Z)
  [5, 1, 2, 6], // right (+X)
  [0, 4, 7, 3], // left (-X)
  [3, 2, 6, 7], // bottom (+Y)
  [0, 1, 5, 4], // top (-Y)
];

const List<List<int>> _kCubeEdges = [
  [0, 1],
  [1, 2],
  [2, 3],
  [3, 0],
  [4, 5],
  [5, 6],
  [6, 7],
  [7, 4],
  [0, 4],
  [1, 5],
  [2, 6],
  [3, 7],
];

const List<Color> _kFaceColors = [
  AppTokens.brand, // Indigo
  AppTokens.brandViolet, // Violet
  Color(0xFFEC4899), // Neon Pink
  AppTokens.brandSky, // Sky
  AppTokens.cashGreen, // Emerald
  AppTokens.debtAmber, // Amber-Gold
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
    // Boost visibility slightly so rear glass faces still glow subtly
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

/// Interactive 3D glassmorphic fintech cube with drag-to-orbit inertia,
/// tap shockwave pulse, nested counter-rotating crystal, and orbital particles.
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
  double _rotX = 0.52;
  double _rotY = 0.74;
  double _rotZ = 0.14;
  double _velX = 0.0;
  double _velY = 0.0;
  double _phase = 0.0;
  double _pulse = 0.0;
  double _introRemaining = 0.0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    if (!widget.continuousSpin) {
      // Smooth 1.1s intro flourish that settles cleanly for battery & widget tests.
      _introRemaining = 1.1;
      _velY = 1.6;
      _velX = 0.45;
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

  @override
  void didUpdateWidget(covariant Interactive3DFintechCube oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.continuousSpin != widget.continuousSpin) {
      _syncTickerState();
    }
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
        _pulse > 0.005 ||
        _velX.abs() > 0.015 ||
        _velY.abs() > 0.015;
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
      if (_pulse > 0) {
        _pulse = math.max(0.0, _pulse - dt * 1.45);
      }

      if (_introRemaining > 0) {
        _introRemaining = math.max(0.0, _introRemaining - dt);
      }

      if (!_dragging) {
        if (widget.continuousSpin) {
          _rotY += dt * 0.85 + _velY * dt;
          _rotX += math.sin(_phase * 1.1) * dt * 0.22 + _velX * dt;
          _rotZ += math.cos(_phase * 0.7) * dt * 0.14;
        } else {
          _rotY += _velY * dt;
          _rotX += _velX * dt;
        }
        final damping = math.pow(0.08, dt).toDouble();
        _velX *= damping;
        _velY *= damping;
        if (_velX.abs() < 0.012) _velX = 0.0;
        if (_velY.abs() < 0.012) _velY = 0.0;
      }
    });

    if (!widget.continuousSpin &&
        !_dragging &&
        _introRemaining <= 0 &&
        _pulse <= 0.005 &&
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
      final dx = details.delta.dx;
      final dy = details.delta.dy;
      _rotY += dx * 0.013;
      _rotX -= dy * 0.013;
      _velY = (dx * 0.45).clamp(-9.0, 9.0);
      _velX = (-dy * 0.45).clamp(-9.0, 9.0);
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!widget.interactive) return;
    final pps = details.velocity.pixelsPerSecond;
    setState(() {
      _dragging = false;
      _velY = (pps.dx * 0.0045).clamp(-8.5, 8.5);
      _velX = (-pps.dy * 0.0045).clamp(-8.5, 8.5);
    });
    widget.onInteractEnd?.call();
    _syncTickerState();
  }

  void _handleTap() {
    if (!widget.interactive) return;
    HapticFeedback.lightImpact();
    widget.onInteractStart?.call();
    setState(() {
      _pulse = 1.0;
      _velY += 4.6;
      _velX += 2.1;
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
    final isDark = isDarkCtx(context);
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
          child: CustomPaint(
            painter: _Cube3DPainter(
              rotX: _rotX,
              rotY: _rotY,
              rotZ: _rotZ,
              phase: _phase,
              pulse: _pulse,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _Cube3DPainter extends CustomPainter {
  final double rotX;
  final double rotY;
  final double rotZ;
  final double phase;
  final double pulse;
  final bool isDark;

  const _Cube3DPainter({
    required this.rotX,
    required this.rotY,
    required this.rotZ,
    required this.phase,
    required this.pulse,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final minDim = math.min(size.width, size.height);

    // 1. Ambient backdrop radial glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppTokens.brandViolet.withValues(alpha: isDark ? 0.34 : 0.22),
          const Color(0xFFEC4899).withValues(alpha: isDark ? 0.16 : 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: minDim * 0.56),
      );
    canvas.drawCircle(center, minDim * 0.56, glowPaint);

    // 2. Tap shockwave ripple
    if (pulse > 0.01) {
      final t = 1.0 - pulse;
      final radius = minDim * (0.28 + 0.24 * t);
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * pulse
        ..color = const Color(0xFFEC4899).withValues(alpha: 0.72 * pulse);
      canvas.drawCircle(center, radius, ringPaint);
    }

    // 3. Orbital 3D particles split by depth (behind vs in front of inner core)
    final fovOuter = minDim * 1.38;
    final particles = <({Offset pos, double z, Color color, double r})>[];
    for (var i = 0; i < 8; i++) {
      final a = phase * 0.9 + (i * math.pi * 0.25);
      final elev = math.sin(phase * 1.3 + i * 0.9) * 0.95;
      final raw = Vec3(
        math.cos(a) * 1.55,
        elev,
        math.sin(a) * 1.55,
      ).rotateX(rotX * 0.4).rotateY(rotY * 0.4);
      final p = project3D(raw, size, fov: fovOuter);
      particles.add((
        pos: p,
        z: raw.z,
        color: _kFaceColors[i % _kFaceColors.length],
        r: (2.0 + (raw.z + 1.6) * 0.75).clamp(1.6, 4.2),
      ));
    }

    void drawParticles({required bool front}) {
      for (final pt in particles) {
        if (front ? pt.z <= 0 : pt.z > 0) continue;
        final alpha = front ? 0.85 : 0.35;
        canvas.drawCircle(
          pt.pos,
          pt.r * 2.1,
          Paint()..color = pt.color.withValues(alpha: alpha * 0.26),
        );
        canvas.drawCircle(
          pt.pos,
          pt.r,
          Paint()..color = pt.color.withValues(alpha: alpha),
        );
      }
    }

    drawParticles(front: false);

    // 4. Outer glassmorphic cube faces (Painter's algorithm: back -> front)
    final scalePulse = 1.0 + 0.06 * math.sin(pulse * math.pi);
    final outerFaces = computeCubeFaces(
      rotX,
      rotY,
      rotZ,
      size,
      scale: scalePulse,
    );

    // Inner counter-rotating wireframe crystal (drawn between back faces & front faces)
    void drawInnerCore() {
      final fovInner = minDim * 0.72 * scalePulse;
      final innerTransformed = _kCubeVertices
          .map((v) => v.rotateX(-rotX * 1.35 + phase * 0.4)
              .rotateY(-rotY * 1.35 + phase * 0.7)
              .rotateZ(rotZ))
          .toList(growable: false);
      final innerProj = innerTransformed
          .map((v) => project3D(v, size, fov: fovInner))
          .toList(growable: false);

      final coreGlow = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.50),
            AppTokens.brandSky.withValues(alpha: 0.32),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: minDim * 0.16));
      canvas.drawCircle(center, minDim * 0.16, coreGlow);

      final edgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.78);
      for (final e in _kCubeEdges) {
        canvas.drawLine(innerProj[e[0]], innerProj[e[1]], edgePaint);
      }
    }

    var coreDrawn = false;
    for (final face in outerFaces) {
      if (!coreDrawn && face.normalZ > 0) {
        drawInnerCore();
        coreDrawn = true;
      }

      final baseColor = _kFaceColors[face.faceIndex % _kFaceColors.length];
      final path = Path()..addPolygon(face.points, true);
      final isFront = face.normalZ >= 0;

      // Dynamic shaded glass surface
      final alpha = isFront
          ? (0.34 + 0.30 * face.light).clamp(0.28, 0.70)
          : (0.14 + 0.14 * face.light).clamp(0.10, 0.32);

      final bounds = path.getBounds();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(baseColor, Colors.white, 0.25 * face.light)!
                .withValues(alpha: alpha),
            baseColor.withValues(alpha: alpha * 0.85),
          ],
        ).createShader(bounds);
      canvas.drawPath(path, fillPaint);

      // Glowing crisp edges
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = isFront ? 1.85 : 0.95
        ..color = isFront
            ? Colors.white.withValues(alpha: 0.55 + 0.30 * face.light)
            : baseColor.withValues(alpha: 0.35);
      canvas.drawPath(path, borderPaint);

      // Subtle inner specular diagonal sheen on front faces
      if (isFront) {
        final sheen = Paint()
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: 0.16 * face.light);
        canvas.drawLine(face.points[0], face.points[2], sheen);
      }
    }
    if (!coreDrawn) {
      drawInnerCore();
    }

    // Specular corner nodes on frontmost faces
    final nodePaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final face in outerFaces) {
      if (face.normalZ <= 0.15) continue;
      for (final pt in face.points) {
        canvas.drawCircle(pt, 2.2, nodePaint);
      }
    }

    drawParticles(front: true);
  }

  @override
  bool shouldRepaint(covariant _Cube3DPainter oldDelegate) =>
      oldDelegate.rotX != rotX ||
      oldDelegate.rotY != rotY ||
      oldDelegate.rotZ != rotZ ||
      oldDelegate.phase != phase ||
      oldDelegate.pulse != pulse ||
      oldDelegate.isDark != isDark;
}

/// Interactive post-login / post-PIN-unlock 3D welcome screen.
/// Shows the draggable 3D fintech cube and auto-enters after a short delay
/// (pausing while the user drags/interacts with the cube).
class Hisobchi3DWelcomeScreen extends StatefulWidget {
  final VoidCallback onContinue;
  final String title;
  final String subtitle;
  final Duration autoContinueDelay;

  const Hisobchi3DWelcomeScreen({
    super.key,
    required this.onContinue,
    this.title = 'Xush kelibsiz!',
    this.subtitle = "Ma'lumotlar sinxronizatsiya qilinmoqda...",
    this.autoContinueDelay = const Duration(milliseconds: 1850),
  });

  @override
  State<Hisobchi3DWelcomeScreen> createState() =>
      _Hisobchi3DWelcomeScreenState();
}

class _Hisobchi3DWelcomeScreenState extends State<Hisobchi3DWelcomeScreen> {
  Timer? _autoTimer;
  bool _completed = false;
  bool _interacted = false;

  @override
  void initState() {
    super.initState();
    _scheduleContinue(widget.autoContinueDelay);
  }

  void _scheduleContinue(Duration delay) {
    _autoTimer?.cancel();
    if (_completed) return;
    _autoTimer = Timer(delay, _finish);
  }

  void _finish() {
    if (_completed || !mounted) return;
    _completed = true;
    _autoTimer?.cancel();
    widget.onContinue();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final bg = isDark ? AppTokens.surfaceDark : AppTokens.surfaceLight;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.15),
                    radius: 0.95,
                    colors: [
                      AppTokens.brandViolet
                          .withValues(alpha: isDark ? 0.30 : 0.16),
                      AppTokens.brand.withValues(alpha: isDark ? 0.15 : 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTokens.brandViolet.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTokens.brandViolet.withValues(alpha: 0.38),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.view_in_ar_rounded,
                              size: 14, color: AppTokens.brandViolet),
                          SizedBox(width: 6),
                          Text(
                            'HISOBCHI • 3D',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                              color: AppTokens.brandViolet,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Interactive3DFintechCube(
                      size: 196,
                      onInteractStart: () {
                        _autoTimer?.cancel();
                        if (!_interacted && mounted) {
                          setState(() => _interacted = true);
                        }
                      },
                      onInteractEnd: () {
                        _scheduleContinue(const Duration(milliseconds: 1400));
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        color: textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _interacted
                          ? "Ajoyib! Istalgan payt kirishingiz mumkin"
                          : widget.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_rounded,
                            size: 15, color: textSecondaryOf(context)),
                        const SizedBox(width: 5),
                        Text(
                          'Kubni barmoq bilan aylantirib ko\'ring',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _finish,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                      label: const Text(
                        'Kirish',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
