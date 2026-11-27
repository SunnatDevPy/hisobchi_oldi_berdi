import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

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

/// Hisobchi — flagman 3D yuklanish (splash) ekrani.
/// Haqiqiy 3D qalinlik, diagonal shisha yaltirashi, akselerometr/barmoq parallaksi,
/// suzuvchi bokeh yulduzchalari, shimmer sarlavha va portal zoom o'tish effekti bilan.
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
  late final AnimationController _introCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );
  late final AnimationController _exitCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  Timer? _exitTriggerTimer;
  Timer? _finishTimer;
  Timer? _stage1Timer;
  Timer? _stage2Timer;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  double _targetGyroX = 0.0;
  double _targetGyroY = 0.0;
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  double _touchTiltX = 0.0;
  double _touchTiltY = 0.0;
  double _tapPulseBoost = 0.0;
  late String _activeSubtitle = widget.subtitle;

  @override
  void initState() {
    super.initState();
    _introCtrl.forward();
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}

    if (widget.subtitle == 'Ilova tayyorlanmoqda...') {
      _stage1Timer = Timer(const Duration(milliseconds: 950), () {
        if (mounted) {
          setState(
              () => _activeSubtitle = 'Kassa va sinxronizatsiya ulanmoqda...');
        }
      });
      _stage2Timer = Timer(const Duration(milliseconds: 1950), () {
        if (mounted) {
          setState(() => _activeSubtitle = 'Hisobchi tayyor!');
        }
      });
    }

    if (!kIsWeb) {
      try {
        _accelSub = accelerometerEventStream().listen(
          (ev) {
            if (!mounted) return;
            // Subtle tilt parallax from gravity vector (±0.18 rad)
            _targetGyroY = (-ev.x / 9.8 * 0.18).clamp(-0.18, 0.18);
            _targetGyroX = (((ev.y - 4.5) / 9.8) * 0.18).clamp(-0.18, 0.18);
          },
          onError: (_) {},
        );
      } catch (_) {}
    }

    if (widget.onFinished != null) {
      final totalMs = widget.duration.inMilliseconds;
      final exitStartMs = math.max(0, totalMs - 300);
      _exitTriggerTimer = Timer(Duration(milliseconds: exitStartMs), () {
        if (mounted) _exitCtrl.forward();
      });
      _finishTimer = Timer(widget.duration, () {
        if (mounted) widget.onFinished!();
      });
    }
  }

  @override
  void dispose() {
    _exitTriggerTimer?.cancel();
    _finishTimer?.cancel();
    _stage1Timer?.cancel();
    _stage2Timer?.cancel();
    _accelSub?.cancel();
    _spin.dispose();
    _orbit.dispose();
    _pulse.dispose();
    _bar.dispose();
    _introCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  void _stepSmoothing() {
    _gyroX += (_targetGyroX - _gyroX) * 0.12;
    _gyroY += (_targetGyroY - _gyroY) * 0.12;
    if (_tapPulseBoost > 0.005) {
      _tapPulseBoost *= 0.90;
    } else {
      _tapPulseBoost = 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final introScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _introCtrl, curve: Curves.easeOutBack),
    );
    final introFade = CurvedAnimation(
      parent: _introCtrl,
      curve: Curves.easeOutCubic,
    );
    final exitScale = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic),
    );
    final exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF161817),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _BottomArcPainter(_pulse)),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _BokehParticlesPainter(_orbit)),
            ),
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge([_introCtrl, _exitCtrl]),
              builder: (context, child) {
                final scale = introScale.value * exitScale.value;
                final opacity =
                    (introFade.value * exitFade.value).clamp(0.0, 1.0);
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildIcon(),
                      const SizedBox(height: 36),
                      _buildShimmerTitle(),
                      const SizedBox(height: 10),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          _activeSubtitle,
                          key: ValueKey<String>(_activeSubtitle),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildBar(),
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

  Widget _buildShimmerTitle() {
    return AnimatedBuilder(
      animation: _bar,
      builder: (context, child) {
        final sweep = -0.35 + 1.70 * _bar.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(sweep - 0.55, -0.2),
            end: Alignment(sweep + 0.55, 0.2),
            colors: const [
              Color(0xFF86EFAC),
              Color(0xFFFFFFFF),
              Color(0xFFFDE68A),
              Color(0xFFFFFFFF),
              Color(0xFF4ADE80),
            ],
            stops: const [0.0, 0.35, 0.50, 0.65, 1.0],
          ).createShader(bounds),
          child: child!,
        );
      },
      child: Text(
        widget.title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        setState(() {
          _touchTiltY = (_touchTiltY + d.delta.dx * 0.008).clamp(-0.55, 0.55);
          _touchTiltX = (_touchTiltX - d.delta.dy * 0.008).clamp(-0.45, 0.45);
        });
      },
      onPanEnd: (_) {
        setState(() {
          _touchTiltX = 0.0;
          _touchTiltY = 0.0;
        });
      },
      onTap: () {
        try {
          HapticFeedback.lightImpact();
        } catch (_) {}
        setState(() => _tapPulseBoost = 1.0);
      },
      child: SizedBox(
        width: 300,
        height: 300,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _orbit, _pulse]),
          builder: (context, _) {
            _stepSmoothing();
            final p = (Curves.easeInOut.transform(_pulse.value) +
                    _tapPulseBoost * 0.45)
                .clamp(0.0, 1.2);
            final totalTiltX = (-0.30 +
                    0.06 * math.sin(_orbit.value * 2 * math.pi) +
                    _gyroX +
                    _touchTiltX)
                .clamp(-0.90, 0.90);
            final totalTiltY = (0.35 +
                    0.08 * math.cos(_orbit.value * 2 * math.pi) +
                    _gyroY +
                    _touchTiltY)
                .clamp(-0.95, 0.95);

            return Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(300, 300),
                  painter: _RippleRingsPainter(_orbit),
                ),
                Transform.translate(
                  offset: Offset(-totalTiltY * 18, totalTiltX * 18),
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF0CCE42)
                              .withValues(alpha: (0.28 + 0.20 * p).clamp(0.0, 0.80)),
                          const Color(0xFFF5C443).withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
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
                    ..rotateX(totalTiltX)
                    ..rotateY(totalTiltY)
                    ..rotateZ(-0.12),
                  child: _buildGlossyTile(
                    size: 164,
                    pulse: p,
                    spin: _spin.value,
                    tiltX: totalTiltX,
                    tiltY: totalTiltY,
                    shimmerPhase: _bar.value,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBar() {
    return SizedBox(
      width: 230,
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(color: Colors.white.withValues(alpha: 0.08)),
            AnimatedBuilder(
              animation: _bar,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_bar.value);
                return Align(
                  alignment: Alignment(-1 + 2 * t, 0),
                  child: FractionallySizedBox(
                    widthFactor: 0.40,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF0CCE42),
                            Color(0xFFF5C443),
                            Colors.white,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0CCE42)
                                .withValues(alpha: 0.70),
                            blurRadius: 11,
                          ),
                        ],
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF5C443)
                                    .withValues(alpha: 0.9),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
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

/// Builds the 3D beveled squircle tile with multi-layer extruded depth,
/// diagonal diagonal glass sheen sweep, and 12-spoke glowing starburst inside.
Widget _buildGlossyTile({
  required double size,
  required double pulse,
  required double spin,
  double tiltX = -0.30,
  double tiltY = 0.35,
  double shimmerPhase = 0.3,
}) {
  final scale = size / 164.0;
  final outerRadius = BorderRadius.circular(44 * scale);
  final innerRadius = BorderRadius.circular(34 * scale);

  return SizedBox(
    width: size,
    height: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        // 4 extruded 3D side/back layers creating solid crystal thickness
        for (int depthIdx = 4; depthIdx >= 1; depthIdx--)
          Transform.translate(
            offset: Offset(
              -tiltY * 5.2 * depthIdx * scale,
              tiltX * 5.2 * depthIdx * scale,
            ),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: outerRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(const Color(0xFF1F382B), const Color(0xFF121815),
                        depthIdx / 4.5)!,
                    Color.lerp(const Color(0xFF0E6837), const Color(0xFF18221D),
                        depthIdx / 4.5)!,
                    Color.lerp(const Color(0xFF282E2C), const Color(0xFF0E1210),
                        depthIdx / 4.5)!,
                  ],
                ),
              ),
            ),
          ),

        // Front glossy glass-bezel face with Figma emerald + gold + clay highlight
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: outerRadius,
            gradient: LinearGradient(
              begin: Alignment(
                -1.0 + 0.45 * math.sin(shimmerPhase * 2 * math.pi),
                -1.0,
              ),
              end: Alignment(
                1.0,
                1.0 + 0.35 * math.cos(shimmerPhase * 2 * math.pi),
              ),
              colors: const [
                Color(0xFF6EE7B7),
                Color(0xFF0CCE42),
                Color(0xFF1E3A2B),
                Color(0xFFD99B26),
              ],
              stops: const [0.0, 0.38, 0.76, 1.0],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.0 * scale,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0CCE42)
                    .withValues(alpha: (0.40 + 0.24 * pulse).clamp(0.0, 0.90)),
                blurRadius: (48 + 20 * pulse) * scale,
                spreadRadius: 2 * scale,
              ),
              BoxShadow(
                color: const Color(0xFFF5C443).withValues(alpha: 0.16),
                blurRadius: 85 * scale,
                spreadRadius: 5 * scale,
              ),
            ],
          ),
          padding: EdgeInsets.all(11 * scale),
          child: ClipRRect(
            borderRadius: innerRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: innerRadius,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF232927), Color(0xFF141716)],
                    ),
                    border: Border.all(
                      color: const Color(0xFF34D399).withValues(alpha: 0.30),
                      width: 1.0 * scale,
                    ),
                  ),
                ),
                CustomPaint(painter: _BurstPainter(spin)),
                // Diagonal sweeping glass reflection across the dark obsidian face
                IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(
                      (-1.1 + 2.2 * shimmerPhase) * size * 0.75,
                      0,
                    ),
                    child: Transform.rotate(
                      angle: -0.55,
                      child: Container(
                        width: size * 0.42,
                        height: size * 1.6,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.13),
                              const Color(0xFF6EE7B7).withValues(alpha: 0.09),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
                      const Color(0xFF0CCE42)
                          .withValues(alpha: 0.26 + 0.16 * _pulse),
                      const Color(0xFFF5C443).withValues(alpha: 0.08),
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
                  tiltX: _tiltX,
                  tiltY: _tiltY,
                  shimmerPhase: 0.5 + 0.5 * math.sin(_phase * 1.4),
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
    this.autoContinueDelay = const Duration(milliseconds: 3200),
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

/// 12 ta yaproqli aylanuvchi "burst" + yumshoq markaziy neon yadro.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Soft luminous emerald-gold core bloom inside cavity
    canvas.drawCircle(
      c,
      size.width * 0.24,
      Paint()
        ..color = const Color(0xFF0CCE42).withValues(alpha: 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

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
        const Color(0xFF10B981),
        const Color(0xFFFEF3C7),
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

/// Suzuvchi mayin zumrad va tilla bokeh zarrachalar qatlami.
class _BokehParticlesPainter extends CustomPainter {
  _BokehParticlesPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  static const _seeds = [
    (x: 0.14, y: 0.16, r: 2.2, b: 3.0, s: 1.0, c: Color(0xFF0CCE42)),
    (x: 0.84, y: 0.18, r: 1.8, b: 2.5, s: 1.4, c: Color(0xFFF5C443)),
    (x: 0.24, y: 0.28, r: 2.8, b: 4.5, s: 0.8, c: Color(0xFF86EFAC)),
    (x: 0.77, y: 0.30, r: 2.4, b: 4.0, s: 1.2, c: Color(0xFF0CCE42)),
    (x: 0.11, y: 0.42, r: 1.9, b: 3.0, s: 1.5, c: Color(0xFFF5C443)),
    (x: 0.89, y: 0.44, r: 2.6, b: 4.5, s: 0.9, c: Color(0xFFD1FAE5)),
    (x: 0.18, y: 0.56, r: 2.2, b: 3.5, s: 1.1, c: Color(0xFF22D666)),
    (x: 0.82, y: 0.58, r: 1.7, b: 2.5, s: 1.3, c: Color(0xFFF5C443)),
    (x: 0.28, y: 0.70, r: 2.5, b: 4.0, s: 1.0, c: Color(0xFF34D399)),
    (x: 0.72, y: 0.72, r: 2.0, b: 3.5, s: 1.4, c: Color(0xFFFDE68A)),
    (x: 0.12, y: 0.80, r: 2.8, b: 5.0, s: 0.7, c: Color(0xFF0CCE42)),
    (x: 0.88, y: 0.82, r: 2.2, b: 4.0, s: 1.2, c: Color(0xFFF5C443)),
    (x: 0.42, y: 0.12, r: 1.6, b: 2.5, s: 1.3, c: Color(0xFFD1FAE5)),
    (x: 0.62, y: 0.14, r: 2.0, b: 3.0, s: 0.9, c: Color(0xFF22D666)),
    (x: 0.38, y: 0.84, r: 2.1, b: 4.0, s: 1.1, c: Color(0xFFF5C443)),
    (x: 0.64, y: 0.86, r: 1.8, b: 3.0, s: 1.5, c: Color(0xFF0CCE42)),
    (x: 0.50, y: 0.10, r: 2.2, b: 4.0, s: 1.0, c: Color(0xFFF5C443)),
    (x: 0.49, y: 0.89, r: 2.4, b: 4.5, s: 0.8, c: Color(0xFFD1FAE5)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * 2 * math.pi;
    for (int i = 0; i < _seeds.length; i++) {
      final pt = _seeds[i];
      final dx = math.sin(t * pt.s + i) * 8.0;
      final dy = math.cos(t * pt.s + i * 0.7) * 10.0;
      final alpha = (0.18 + 0.32 * (0.5 + 0.5 * math.sin(t * 2 + i * 1.1)))
          .clamp(0.10, 0.55);
      canvas.drawCircle(
        Offset(size.width * pt.x + dx, size.height * pt.y + dy),
        pt.r,
        Paint()
          ..color = pt.c.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pt.b),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BokehParticlesPainter old) => false;
}

/// Ikonka ortidan tashqariga silliq tarqaluvchi kosmik energiya to'lqinlari.
class _RippleRingsPainter extends CustomPainter {
  _RippleRingsPainter(this.anim) : super(repaint: anim);
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final minR = size.width * 0.24;
    final maxR = size.width * 0.49;

    for (var i = 0; i < 3; i++) {
      final k = ((anim.value * 3.0) + i / 3.0) % 1.0;
      final r = minR + (maxR - minR) * k;
      final fade = (1.0 - k);
      final alpha = (0.28 * fade * fade).clamp(0.0, 0.30);
      if (alpha <= 0.005) continue;
      final color = i.isEven
          ? const Color(0xFF0CCE42)
          : const Color(0xFFF5C443);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RippleRingsPainter old) => false;
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
          ..color = const Color(0xFFF5C443).withValues(alpha: 0.75)
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

/// Ekran pastidagi yorqin zumrad yoy.
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
            const Color(0xFF0A8F32).withValues(alpha: 0.34 + 0.14 * p),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFF28E070).withValues(alpha: 0.80)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFA7F3D0).withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _BottomArcPainter old) => false;
}

/// Finite-animation 3D crystal squircle emblem for Login & PIN lock screens.
/// Uses intro + spring-back controllers only (zero repeating tickers) so UI
/// frames and `pumpAndSettle()` stay fast and deterministic.
class Hisobchi3DEmblem extends StatefulWidget {
  final double size;
  final bool showOrbitRings;
  final bool interactive;

  const Hisobchi3DEmblem({
    super.key,
    this.size = 118,
    this.showOrbitRings = true,
    this.interactive = true,
  });

  @override
  State<Hisobchi3DEmblem> createState() => _Hisobchi3DEmblemState();
}

class _Hisobchi3DEmblemState extends State<Hisobchi3DEmblem>
    with TickerProviderStateMixin {
  late final AnimationController _introCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  late final AnimationController _springCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  double _touchTiltX = 0.0;
  double _touchTiltY = 0.0;
  double _releaseStartX = 0.0;
  double _releaseStartY = 0.0;
  double _tapBoost = 0.0;

  @override
  void initState() {
    super.initState();
    _springCtrl.addListener(_onSpringTick);
  }

  void _onSpringTick() {
    if (!mounted) return;
    final t = Curves.easeOutCubic.transform(_springCtrl.value);
    setState(() {
      _touchTiltX = _releaseStartX * (1.0 - t);
      _touchTiltY = _releaseStartY * (1.0 - t);
      if (_tapBoost > 0) {
        _tapBoost = (1.0 - t).clamp(0.0, 1.0);
      }
    });
  }

  @override
  void dispose() {
    _springCtrl.removeListener(_onSpringTick);
    _introCtrl.dispose();
    _springCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boxSize = widget.size * (widget.showOrbitRings ? 1.62 : 1.32);
    final introScale = Tween<double>(begin: 0.84, end: 1.0).animate(
      CurvedAnimation(parent: _introCtrl, curve: Curves.easeOutBack),
    );
    final introFade = CurvedAnimation(
      parent: _introCtrl,
      curve: Curves.easeOutCubic,
    );

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: widget.interactive
            ? (_) {
                if (_springCtrl.isAnimating) _springCtrl.stop();
              }
            : null,
        onPanUpdate: widget.interactive
            ? (d) {
                setState(() {
                  _touchTiltY =
                      (_touchTiltY + d.delta.dx * 0.008).clamp(-0.52, 0.52);
                  _touchTiltX =
                      (_touchTiltX - d.delta.dy * 0.008).clamp(-0.42, 0.42);
                });
              }
            : null,
        onPanEnd: widget.interactive
            ? (_) {
                _releaseStartX = _touchTiltX;
                _releaseStartY = _touchTiltY;
                _springCtrl.forward(from: 0);
              }
            : null,
        onTap: widget.interactive
            ? () {
                try {
                  HapticFeedback.lightImpact();
                } catch (_) {}
                _releaseStartX = _touchTiltX;
                _releaseStartY = _touchTiltY;
                setState(() => _tapBoost = 1.0);
                _springCtrl.forward(from: 0);
              }
            : null,
        child: SizedBox(
          width: boxSize,
          height: boxSize,
          child: AnimatedBuilder(
            animation: _introCtrl,
            builder: (context, child) => Opacity(
              opacity: introFade.value.clamp(0.0, 1.0),
              child: Transform.scale(scale: introScale.value, child: child),
            ),
            child: Builder(
              builder: (context) {
                final tiltX = (-0.28 + _touchTiltX).clamp(-0.85, 0.85);
                final tiltY = (0.32 + _touchTiltY).clamp(-0.85, 0.85);
                final pulse = (0.55 + _tapBoost * 0.45).clamp(0.0, 1.0);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(-tiltY * 12, tiltX * 12),
                      child: Container(
                        width: boxSize * 0.94,
                        height: boxSize * 0.94,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF0CCE42)
                                  .withValues(alpha: 0.26 + 0.16 * pulse),
                              const Color(0xFFF5C443).withValues(alpha: 0.09),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                    if (widget.showOrbitRings)
                      CustomPaint(
                        size: Size(boxSize, boxSize),
                        painter: _OrbitPainter(0.28),
                      ),
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateX(tiltX)
                        ..rotateY(tiltY)
                        ..rotateZ(-0.10),
                      child: _buildGlossyTile(
                        size: widget.size,
                        pulse: pulse,
                        spin: 0.18,
                        tiltX: tiltX,
                        tiltY: tiltY,
                        shimmerPhase: 0.34,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Static soft violet-orchid bottom horizon glow arc matching HisobchiSplash.
class HisobchiBottomHorizonArc extends StatelessWidget {
  const HisobchiBottomHorizonArc({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: const _StaticHorizonArcPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StaticHorizonArcPainter extends CustomPainter {
  const _StaticHorizonArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final rect = Rect.fromCenter(
      center: Offset(w / 2, size.height + w * 0.38),
      width: w * 1.7,
      height: w * 0.90,
    );

    canvas.drawOval(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A8F32).withValues(alpha: 0.32),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..color = const Color(0xFF28E070).withValues(alpha: 0.62)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = const Color(0xFFA7F3D0).withValues(alpha: 0.72),
    );
  }

  @override
  bool shouldRepaint(covariant _StaticHorizonArcPainter oldDelegate) => false;
}
