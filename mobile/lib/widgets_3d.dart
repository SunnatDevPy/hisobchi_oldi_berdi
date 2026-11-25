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

/// Depth-sorted projected quad representing one face of a 3D solid.
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

/// Precomputed G2-smooth superellipse (squircle) unit contour points `(x, y)` in `[-1, 1]`.
final List<Offset> _kSquircleContour = List<Offset>.generate(56, (i) {
  final theta = (i / 56.0) * 2.0 * math.pi;
  final ct = math.cos(theta);
  final st = math.sin(theta);
  const exp = 2.0 / 4.35; // Smooth iOS/fintech squircle curvature
  final sx = ct == 0 ? 0.0 : ct.sign * math.pow(ct.abs(), exp).toDouble();
  final sy = st == 0 ? 0.0 : st.sign * math.pow(st.abs(), exp).toDouble();
  return Offset(sx, sy);
}, growable: false);

/// Interactive 3D glossy beveled violet-magenta squircle block housing a
/// 12-spoke neon pink-white starburst spinner and gossamer orbital trails.
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
  // Base showcase pose matching the tilted 3D glossy squircle in the reference design.
  static const double _baseRotX = -0.24;
  static const double _baseRotY = 0.38;
  static const double _baseRotZ = -0.11;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _rotX = _baseRotX;
  double _rotY = _baseRotY;
  double _rotZ = _baseRotZ;
  double _userOffsetX = 0.0;
  double _userOffsetY = 0.0;
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
      // Smooth 1.1s 3D entrance settle so LoginScreen stays lively yet test-friendly.
      _introRemaining = 1.1;
      _userOffsetY = -0.55;
      _userOffsetX = 0.28;
      _velY = 1.35;
      _velX = -0.55;
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
      if (_pulse > 0) {
        _pulse = math.max(0.0, _pulse - dt * 1.5);
      }
      if (_introRemaining > 0) {
        _introRemaining = math.max(0.0, _introRemaining - dt);
      }

      if (!_dragging) {
        _userOffsetY += _velY * dt;
        _userOffsetX += _velX * dt;

        final damping = math.pow(0.06, dt).toDouble();
        _velX *= damping;
        _velY *= damping;

        // Gently spring back toward the hero showcase tilt while floating smoothly
        final spring = (dt * 2.6).clamp(0.0, 0.25);
        _userOffsetX *= (1.0 - spring * 0.45);
        _userOffsetY *= (1.0 - spring * 0.35);

        if (_velX.abs() < 0.010) _velX = 0.0;
        if (_velY.abs() < 0.010) _velY = 0.0;
      }

      if (widget.continuousSpin) {
        final floatX = math.sin(_phase * 1.55) * 0.11;
        final floatY = math.cos(_phase * 1.15) * 0.16;
        final floatZ = math.sin(_phase * 0.95) * 0.05;
        _rotX = (_baseRotX + floatX + _userOffsetX).clamp(-1.15, 1.15);
        _rotY = _baseRotY + floatY + _userOffsetY;
        _rotZ = _baseRotZ + floatZ;
      } else {
        _rotX = (_baseRotX + _userOffsetX).clamp(-1.15, 1.15);
        _rotY = _baseRotY + _userOffsetY;
        _rotZ = _baseRotZ;
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
      _userOffsetY += dx * 0.012;
      _userOffsetX = (_userOffsetX - dy * 0.012).clamp(-0.95, 0.95);
      _velY = (dx * 0.38).clamp(-7.5, 7.5);
      _velX = (-dy * 0.38).clamp(-7.5, 7.5);
      _rotX = (_baseRotX + _userOffsetX).clamp(-1.15, 1.15);
      _rotY = _baseRotY + _userOffsetY;
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!widget.interactive) return;
    final pps = details.velocity.pixelsPerSecond;
    setState(() {
      _dragging = false;
      _velY = (pps.dx * 0.0038).clamp(-7.5, 7.5);
      _velX = (-pps.dy * 0.0038).clamp(-7.5, 7.5);
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
      _velY += 3.2;
      _velX -= 1.2;
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
            painter: _GlossySquircle3DPainter(
              rotX: _rotX,
              rotY: _rotY,
              rotZ: _rotZ,
              phase: _phase,
              pulse: _pulse,
            ),
          ),
        ),
      ),
    );
  }
}

class _BevelQuad {
  final List<Offset> pts;
  final double avgZ;
  final Color color;

  const _BevelQuad({
    required this.pts,
    required this.avgZ,
    required this.color,
  });
}

class _GlossySquircle3DPainter extends CustomPainter {
  final double rotX;
  final double rotY;
  final double rotZ;
  final double phase;
  final double pulse;

  const _GlossySquircle3DPainter({
    required this.rotX,
    required this.rotY,
    required this.rotZ,
    required this.phase,
    required this.pulse,
  });

  Vec3 _xform(double x, double y, double z) =>
      Vec3(x, y, z).rotateX(rotX).rotateY(rotY).rotateZ(rotZ);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final minDim = math.min(size.width, size.height);
    final breathe = 1.0 + 0.028 * math.sin(phase * 2.4) + 0.05 * math.sin(pulse * math.pi);
    final fov = minDim * 1.48 * breathe;

    // 1. Soft multi-stop magenta-violet aura directly behind the 3D block
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF472B6).withValues(alpha: 0.42),
          const Color(0xFFA855F7).withValues(alpha: 0.28),
          const Color(0xFF581C87).withValues(alpha: 0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 0.36, 0.68, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: minDim * 0.56));
    canvas.drawCircle(center, minDim * 0.56, auraPaint);

    // Optional tap shockwave halo
    if (pulse > 0.01) {
      final t = 1.0 - pulse;
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * pulse
        ..color = const Color(0xFFF9A8D4).withValues(alpha: 0.75 * pulse);
      canvas.drawCircle(center, minDim * (0.34 + 0.22 * t), ringPaint);
    }

    // 2. Compute 3D orbital gossamer light trails (split into back z < 0 & front z >= 0)
    final orbitSegments = <({Offset p1, Offset p2, double z, double alpha})>[];
    for (var ringIdx = 0; ringIdx < 2; ringIdx++) {
      final tiltX = ringIdx == 0 ? 0.52 : -0.38;
      final tiltY = ringIdx == 0 ? -0.34 : 0.48;
      final tiltZ = ringIdx == 0 ? -0.38 : 0.32;
      final radiusX = ringIdx == 0 ? 1.30 : 1.24;
      final radiusY = ringIdx == 0 ? 1.12 : 1.20;
      final spinSpeed = ringIdx == 0 ? 0.85 : -0.68;
      const steps = 44;

      Vec3? prev3;
      Offset? prev2;
      for (var s = 0; s <= steps; s++) {
        final u = s / steps;
        final a = u * 2.0 * math.pi + phase * spinSpeed;
        final v = Vec3(math.cos(a) * radiusX, math.sin(a) * radiusY, 0.0)
            .rotateX(tiltX + rotX * 0.35)
            .rotateY(tiltY + rotY * 0.35)
            .rotateZ(tiltZ);
        final p = project3D(v, size, fov: fov);
        if (prev3 != null && prev2 != null) {
          // Tapered comet intensity along each ring
          final comet = 0.5 + 0.5 * math.sin(u * 2.0 * math.pi * 2.0 - phase * 2.2 + ringIdx * 1.7);
          final alpha = (0.08 + 0.44 * math.pow(comet, 2.2)).clamp(0.05, 0.58);
          orbitSegments.add((
            p1: prev2,
            p2: p,
            z: (prev3.z + v.z) * 0.5,
            alpha: alpha,
          ));
        }
        prev3 = v;
        prev2 = p;
      }
    }

    void drawOrbitHalf({required bool front}) {
      for (final seg in orbitSegments) {
        if (front ? seg.z < 0.02 : seg.z >= 0.02) continue;
        final mul = front ? 1.0 : 0.45;
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = front ? 1.35 : 0.95
          ..color = Color.lerp(
            const Color(0xFFF472B6),
            Colors.white,
            seg.alpha,
          )!
              .withValues(alpha: seg.alpha * mul);
        canvas.drawLine(seg.p1, seg.p2, p);
      }
    }

    drawOrbitHalf(front: false);

    // 3. Build 3-ring cushioned 3D squircle extrusion:
    //    back ring (z = -0.25, scale = 0.96)
    //    mid bulge (z =  0.00, scale = 1.04)
    //    front ring (z = +0.25, scale = 0.99)
    const zBack = -0.25;
    const zMid = 0.0;
    const zFront = 0.25;
    final nPts = _kSquircleContour.length;

    final ringBack3 = <Vec3>[];
    final ringMid3 = <Vec3>[];
    final ringFront3 = <Vec3>[];
    final ringBack2 = <Offset>[];
    final ringMid2 = <Offset>[];
    final ringFront2 = <Offset>[];

    for (var i = 0; i < nPts; i++) {
      final c = _kSquircleContour[i];
      final vb = _xform(c.dx * 0.96, c.dy * 0.96, zBack);
      final vm = _xform(c.dx * 1.045, c.dy * 1.045, zMid);
      final vf = _xform(c.dx * 0.99, c.dy * 0.99, zFront);
      ringBack3.add(vb);
      ringMid3.add(vm);
      ringFront3.add(vf);
      ringBack2.add(project3D(vb, size, fov: fov));
      ringMid2.add(project3D(vm, size, fov: fov));
      ringFront2.add(project3D(vf, size, fov: fov));
    }

    final keyLight = const Vec3(-0.58, -0.68, 0.45).normalized();
    final rimLight = const Vec3(0.62, 0.52, 0.58).normalized();

    Color shadeBevelNormal(Vec3 normal) {
      final keyDot = normal.dot(keyLight).clamp(0.0, 1.0);
      final rimDot = normal.dot(rimLight).clamp(0.0, 1.0);
      final spec = math.pow(keyDot, 9.0).toDouble();

      // Deep glossy amethyst base -> electric magenta-purple -> hot pink -> white chrome specular
      var col = Color.lerp(
        const Color(0xFF1E093E),
        const Color(0xFF9333EA),
        (keyDot * 0.85 + 0.15).clamp(0.0, 1.0),
      )!;
      col = Color.lerp(col, const Color(0xFFEC4899), (rimDot * 0.65).clamp(0.0, 1.0))!;
      col = Color.lerp(col, const Color(0xFFFDF2F8), (spec * 0.92).clamp(0.0, 1.0))!;
      return col;
    }

    final sideQuads = <_BevelQuad>[];
    for (var i = 0; i < nPts; i++) {
      final j = (i + 1) % nPts;

      // Back -> Mid bevel band
      final bm0 = ringBack3[i];
      final bm1 = ringBack3[j];
      final bm2 = ringMid3[j];
      final bm3 = ringMid3[i];
      final n1 = (bm1 - bm0).cross(bm3 - bm0).normalized();
      sideQuads.add(
        _BevelQuad(
          pts: [ringBack2[i], ringBack2[j], ringMid2[j], ringMid2[i]],
          avgZ: (bm0.z + bm1.z + bm2.z + bm3.z) * 0.25,
          color: shadeBevelNormal(n1),
        ),
      );

      // Mid -> Front bevel band
      final mf0 = ringMid3[i];
      final mf1 = ringMid3[j];
      final mf2 = ringFront3[j];
      final mf3 = ringFront3[i];
      final n2 = (mf1 - mf0).cross(mf3 - mf0).normalized();
      sideQuads.add(
        _BevelQuad(
          pts: [ringMid2[i], ringMid2[j], ringFront2[j], ringFront2[i]],
          avgZ: (mf0.z + mf1.z + mf2.z + mf3.z) * 0.25,
          color: shadeBevelNormal(n2),
        ),
      );
    }

    sideQuads.sort((a, b) => a.avgZ.compareTo(b.avgZ));

    final frontNormal = _xform(0, 0, 1);
    final showFrontOnTop = frontNormal.z >= 0;

    void drawCapFace({required bool isFront}) {
      final zPlane = isFront ? zFront : zBack;
      final outer2 = isFront ? ringFront2 : ringBack2;
      final outerPath = Path()..addPolygon(outer2, true);
      final outerBounds = outerPath.getBounds();

      // Glossy metallic-glass outer bezel frame
      final bezelPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xFFFCE7F3),
            Color(0xFFC084FC),
            Color(0xFF581C87),
            Color(0xFF2E1065),
            Color(0xFFDB2777),
          ],
          stops: const [0.0, 0.22, 0.54, 0.78, 1.0],
        ).createShader(outerBounds);
      canvas.drawPath(outerPath, bezelPaint);

      // Inner recessed dark obsidian cavity (scale = 0.82)
      final inner2 = <Offset>[];
      for (var i = 0; i < nPts; i++) {
        final c = _kSquircleContour[i];
        final v = _xform(c.dx * 0.82, c.dy * 0.82, zPlane + (isFront ? 0.004 : -0.004));
        inner2.add(project3D(v, size, fov: fov));
      }
      final innerPath = Path()..addPolygon(inner2, true);
      final innerBounds = innerPath.getBounds();

      final cavityPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -0.15),
          radius: 0.95,
          colors: const [
            Color(0xFF1A0E33),
            Color(0xFF0B0618),
            Color(0xFF05030C),
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(innerBounds);
      canvas.drawPath(innerPath, cavityPaint);

      // Subtle purple inner ambient glow under the 12-spoke starburst
      final centerFace = project3D(_xform(0, 0, zPlane), size, fov: fov);
      final centerGlow = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFEC4899).withValues(alpha: 0.30),
            const Color(0xFF9333EA).withValues(alpha: 0.14),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: centerFace, radius: minDim * 0.26));
      canvas.drawCircle(centerFace, minDim * 0.26, centerGlow);

      // 12-Spoke Glowing Pink-White Radial Starburst Loader projected in 3D!
      const bladeCount = 12;
      const rInner = 0.215;
      const rOuter = 0.545;
      const halfAngInner = 0.115; // radians (~6.6 deg half-width)
      const halfAngOuter = 0.128; // slightly wider outer flare like reference
      final zStar = zPlane + (isFront ? 0.014 : -0.014);
      final slowTurn = phase * 0.38;
      final waveHead = (phase * 1.55) % 1.0; // 0..1 sweeping around the 12 spokes

      for (var b = 0; b < bladeCount; b++) {
        final frac = b / bladeCount;
        // Clockwise distance behind the sweeping bright wave head
        final dist = (waveHead - frac + 1.0) % 1.0;
        final intensity = math.pow(1.0 - dist, 2.35).toDouble().clamp(0.0, 1.0);

        final midA = frac * 2.0 * math.pi - math.pi * 0.5 + slowTurn;
        final dirSign = isFront ? 1.0 : -1.0;
        final a = midA * dirSign;

        // 6-point rounded-tip wedge in 3D face space
        final p0 = _xform(
          math.cos(a - halfAngInner) * rInner,
          math.sin(a - halfAngInner) * rInner,
          zStar,
        );
        final p1 = _xform(
          math.cos(a) * (rInner * 0.95),
          math.sin(a) * (rInner * 0.95),
          zStar,
        );
        final p2 = _xform(
          math.cos(a + halfAngInner) * rInner,
          math.sin(a + halfAngInner) * rInner,
          zStar,
        );
        final p3 = _xform(
          math.cos(a + halfAngOuter) * (rOuter * 0.95),
          math.sin(a + halfAngOuter) * (rOuter * 0.95),
          zStar,
        );
        final p4 = _xform(
          math.cos(a) * rOuter,
          math.sin(a) * rOuter,
          zStar,
        );
        final p5 = _xform(
          math.cos(a - halfAngOuter) * (rOuter * 0.95),
          math.sin(a - halfAngOuter) * (rOuter * 0.95),
          zStar,
        );

        final poly = [
          project3D(p0, size, fov: fov),
          project3D(p1, size, fov: fov),
          project3D(p2, size, fov: fov),
          project3D(p3, size, fov: fov),
          project3D(p4, size, fov: fov),
          project3D(p5, size, fov: fov),
        ];
        final bladePath = Path()..addPolygon(poly, true);

        final innerCol = Color.lerp(
          const Color(0xFF9333EA),
          const Color(0xFFF9A8D4),
          intensity,
        )!;
        final outerCol = Color.lerp(
          const Color(0xFFEC4899),
          const Color(0xFFFFFFFF),
          (intensity * 1.15).clamp(0.0, 1.0),
        )!;

        // Soft neon bloom behind the brightest leading blades
        if (intensity > 0.35) {
          final tip2D = poly[4];
          canvas.drawCircle(
            tip2D,
            minDim * (0.045 + 0.035 * intensity),
            Paint()
              ..color = const Color(0xFFF472B6)
                  .withValues(alpha: 0.34 * intensity),
          );
        }

        final bladeAlpha = (0.48 + 0.52 * intensity).clamp(0.45, 1.0);
        final bladePaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              innerCol.withValues(alpha: bladeAlpha),
              outerCol.withValues(alpha: bladeAlpha),
            ],
          ).createShader(bladePath.getBounds());
        canvas.drawPath(bladePath, bladePaint);
      }

      // Glossy diagonal crystal reflection across upper-left half of inner face
      canvas.save();
      canvas.clipPath(innerPath);
      final sheenPath = Path()
        ..moveTo(innerBounds.left - 10, innerBounds.top - 10)
        ..lineTo(innerBounds.right + 10, innerBounds.top - 10)
        ..lineTo(
          innerBounds.left + innerBounds.width * 0.18,
          innerBounds.bottom * 0.92,
        )
        ..lineTo(innerBounds.left - 10, innerBounds.bottom * 0.65)
        ..close();
      canvas.drawPath(
        sheenPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.13),
              const Color(0xFFF9A8D4).withValues(alpha: 0.05),
              Colors.transparent,
            ],
          ).createShader(innerBounds),
      );
      canvas.restore();

      // Inner cavity rim highlight & outer specular edge highlight
      canvas.drawPath(
        innerPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF9A8D4).withValues(alpha: 0.70),
              const Color(0xFF7E22CE).withValues(alpha: 0.35),
              const Color(0xFFF472B6).withValues(alpha: 0.60),
            ],
          ).createShader(innerBounds),
      );

      canvas.drawPath(
        outerPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.92),
              const Color(0xFFF472B6).withValues(alpha: 0.65),
              const Color(0xFF6B21A8).withValues(alpha: 0.30),
              const Color(0xFFF9A8D4).withValues(alpha: 0.78),
            ],
            stops: const [0.0, 0.28, 0.68, 1.0],
          ).createShader(outerBounds),
      );
    }

    // Painter's order: far cap -> sorted 3D curved bevel quads -> near cap
    drawCapFace(isFront: !showFrontOnTop);

    final quadPaint = Paint()..style = PaintingStyle.fill;
    final seamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..strokeJoin = StrokeJoin.round;
    for (final q in sideQuads) {
      final path = Path()..addPolygon(q.pts, true);
      quadPaint.color = q.color;
      seamPaint.color = q.color;
      canvas.drawPath(path, quadPaint);
      canvas.drawPath(path, seamPaint);
    }

    drawCapFace(isFront: showFrontOnTop);

    // Front-half gossamer orbital streaks & tiny glowing sparkle nodes
    drawOrbitHalf(front: true);
    for (var k = 0; k < 4; k++) {
      final a = phase * 1.1 + k * (math.pi * 0.5);
      final sv = Vec3(math.cos(a) * 1.28, math.sin(a * 1.3) * 0.95, math.sin(a) * 0.6)
          .rotateX(rotX * 0.4)
          .rotateY(rotY * 0.4);
      if (sv.z < 0) continue;
      final sp = project3D(sv, size, fov: fov);
      canvas.drawCircle(
        sp,
        3.8,
        Paint()..color = const Color(0xFFF472B6).withValues(alpha: 0.32),
      );
      canvas.drawCircle(
        sp,
        1.5,
        Paint()..color = Colors.white.withValues(alpha: 0.92),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlossySquircle3DPainter oldDelegate) =>
      oldDelegate.rotX != rotX ||
      oldDelegate.rotY != rotY ||
      oldDelegate.rotZ != rotZ ||
      oldDelegate.phase != phase ||
      oldDelegate.pulse != pulse;
}

/// Shared obsidian + vertical violet light pillar + bottom curved neon horizon
/// backdrop matching the dark purple fintech splash aesthetic.
class HisobchiCosmicSplashScene extends StatelessWidget {
  final Widget child;
  final double pulse;

  const HisobchiCosmicSplashScene({
    super.key,
    required this.child,
    this.pulse = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF070510),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Subtle starry ambient purple aura + vertical light beam
          IgnorePointer(
            child: CustomPaint(
              painter: _CosmicBeamAndHorizonPainter(pulse: pulse),
            ),
          ),
          // 2. Foreground content
          child,
        ],
      ),
    );
  }
}

class _CosmicBeamAndHorizonPainter extends CustomPainter {
  final double pulse;

  const _CosmicBeamAndHorizonPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final emblemCenterY = size.height * 0.43;

    // Wide ambient violet radial nebula
    final nebulaRect = Rect.fromCircle(
      center: Offset(cx, emblemCenterY),
      radius: math.min(size.width, size.height) * (0.62 + 0.04 * pulse),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.14),
          radius: 0.72 + 0.05 * pulse,
          colors: [
            const Color(0xFFA855F7).withValues(alpha: 0.30 + 0.08 * pulse),
            const Color(0xFFEC4899).withValues(alpha: 0.14 + 0.04 * pulse),
            const Color(0xFF3B0764).withValues(alpha: 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.34, 0.64, 1.0],
        ).createShader(nebulaRect),
    );

    // Vertical luminous light pillar passing behind the 3D squircle
    final beamHeight = size.height * 0.74;
    final beamTop = emblemCenterY - beamHeight * 0.5;
    final outerBeamRect = Rect.fromLTWH(cx - 72, beamTop, 144, beamHeight);
    canvas.drawRect(
      outerBeamRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            const Color(0xFF9333EA).withValues(alpha: 0.16 + 0.06 * pulse),
            const Color(0xFFE879F9).withValues(alpha: 0.30 + 0.10 * pulse),
            const Color(0xFF9333EA).withValues(alpha: 0.16 + 0.06 * pulse),
            Colors.transparent,
          ],
          stops: const [0.0, 0.28, 0.50, 0.72, 1.0],
        ).createShader(outerBeamRect),
    );

    // Vertical fade mask effect via bright core flare above & below emblem
    final coreBeamRect =
        Rect.fromLTWH(cx - 18, emblemCenterY - 210, 36, 420);
    canvas.drawRect(
      coreBeamRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFFF5D0FE).withValues(alpha: 0.42 + 0.14 * pulse),
            const Color(0xFFFFFFFF).withValues(alpha: 0.58 + 0.14 * pulse),
            const Color(0xFFF5D0FE).withValues(alpha: 0.42 + 0.14 * pulse),
            Colors.transparent,
          ],
          stops: const [0.0, 0.27, 0.50, 0.73, 1.0],
        ).createShader(coreBeamRect),
    );

    // Subtle static cosmic starlight specks
    final starPaint = Paint();
    const starSeeds = [
      Offset(0.16, 0.22),
      Offset(0.84, 0.20),
      Offset(0.22, 0.34),
      Offset(0.79, 0.36),
      Offset(0.14, 0.54),
      Offset(0.87, 0.52),
      Offset(0.28, 0.64),
      Offset(0.73, 0.62),
    ];
    for (var i = 0; i < starSeeds.length; i++) {
      final s = starSeeds[i];
      final twinkle = 0.25 + 0.45 * (0.5 + 0.5 * math.sin(pulse * math.pi * 2 + i));
      starPaint.color = Colors.white.withValues(alpha: twinkle * 0.45);
      canvas.drawCircle(
        Offset(size.width * s.dx, size.height * s.dy),
        i.isEven ? 1.2 : 0.9,
        starPaint,
      );
    }

    // Bottom curved glowing purple-magenta horizon arc (planet limb glow)
    final arcRadius = size.width * 1.45;
    final arcCenter = Offset(cx, size.height + arcRadius - 42);

    // Soft atmospheric bloom rising from the curved horizon
    final horizonGlowRect =
        Rect.fromLTWH(0, size.height - 130, size.width, 140);
    canvas.drawRect(
      horizonGlowRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.25),
          radius: 1.05,
          colors: [
            const Color(0xFFD946EF).withValues(alpha: 0.42 + 0.08 * pulse),
            const Color(0xFF7C3AED).withValues(alpha: 0.22),
            Colors.transparent,
          ],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(horizonGlowRect),
    );

    // Crisp glowing curved horizon rim
    for (final layer in const [
      (width: 18.0, alpha: 0.16, color: Color(0xFFA855F7)),
      (width: 7.0, alpha: 0.34, color: Color(0xFFEC4899)),
      (width: 2.2, alpha: 0.72, color: Color(0xFFF5D0FE)),
    ]) {
      canvas.drawCircle(
        arcCenter,
        arcRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer.width
          ..color = layer.color.withValues(alpha: layer.alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CosmicBeamAndHorizonPainter oldDelegate) =>
      (oldDelegate.pulse - pulse).abs() > 0.004;
}

/// Cinematic 3–4s post-login / post-PIN-unlock 3D welcome transition screen.
class Hisobchi3DWelcomeScreen extends StatefulWidget {
  final VoidCallback onContinue;
  final String title;
  final String subtitle;
  final Duration autoContinueDelay;

  const Hisobchi3DWelcomeScreen({
    super.key,
    required this.onContinue,
    this.title = 'Hisobchi',
    this.subtitle = "Ma'lumotlar sinxronizatsiya qilinmoqda...",
    this.autoContinueDelay = const Duration(milliseconds: 3200),
  });

  @override
  State<Hisobchi3DWelcomeScreen> createState() =>
      _Hisobchi3DWelcomeScreenState();
}

class _Hisobchi3DWelcomeScreenState extends State<Hisobchi3DWelcomeScreen>
    with SingleTickerProviderStateMixin {
  Timer? _autoTimer;
  late final AnimationController _pulseCtrl;
  bool _completed = false;
  bool _interacted = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
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
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070510),
      body: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, child) => HisobchiCosmicSplashScene(
          pulse: _pulseCtrl.value,
          child: child!,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Interactive3DFintechCube(
                        size: 214,
                        onInteractStart: () {
                          _autoTimer?.cancel();
                          if (!_interacted && mounted) {
                            setState(() => _interacted = true);
                          }
                        },
                        onInteractEnd: () {
                          _scheduleContinue(
                              const Duration(milliseconds: 1600));
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _interacted
                            ? 'Davom etish uchun pastdagi tugmani bosing'
                            : widget.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.85),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(
                          color: const Color(0xFFE879F9).withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    onPressed: _finish,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                    label: const Text(
                      'Kirish',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
