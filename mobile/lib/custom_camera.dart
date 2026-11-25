import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'platform_bridge_types.dart';
import 'theme.dart';
import 'widgets.dart';

// ============================================================================
// PURE HELPERS (unit-tested): tilt, frame geometry, crop, quality, stitching
// ============================================================================

enum TiltLevel { good, warn, bad }

/// How far the phone is from being parallel to a flat sheet (or perfectly
/// upright for a wall-mounted sheet), in degrees. Input is accelerometer m/s².
double tiltDeviationDegrees(double x, double y, double z) {
  final g = math.sqrt(x * x + y * y + z * z);
  if (g < 1e-3) return 0;
  final c = (z.abs() / g).clamp(0.0, 1.0);
  final tilt = math.acos(c) * 180 / math.pi;
  return tilt < 45 ? tilt : 90 - tilt;
}

TiltLevel tiltLevelFor(double deviationDeg) {
  if (deviationDeg <= 4) return TiltLevel.good;
  if (deviationDeg <= 10) return TiltLevel.warn;
  return TiltLevel.bad;
}

/// Frame rectangle expressed as fractions (0..1) of the preview.
class FrameFractions {
  final double left;
  final double top;
  final double width;
  final double height;

  const FrameFractions(this.left, this.top, this.width, this.height);

  static const FrameFractions full = FrameFractions(0, 0, 1, 1);

  static FrameFractions lerp(FrameFractions a, FrameFractions b, double t) =>
      FrameFractions(
        a.left + (b.left - a.left) * t,
        a.top + (b.top - a.top) * t,
        a.width + (b.width - a.width) * t,
        a.height + (b.height - a.height) * t,
      );

  Rect toRect(Size size) => Rect.fromLTWH(
        left * size.width,
        top * size.height,
        width * size.width,
        height * size.height,
      );
}

const FrameFractions kPortraitFrame = FrameFractions(0.07, 0.12, 0.86, 0.76);
const FrameFractions kLandscapeFrame = FrameFractions(0.05, 0.28, 0.90, 0.44);

FrameFractions documentFrameFractions({required bool landscape}) =>
    landscape ? kLandscapeFrame : kPortraitFrame;

class CapturedProcessRequest {
  final Uint8List bytes;
  final double left;
  final double top;
  final double width;
  final double height;
  final int rotateQuarter;
  final int maxSide;

  const CapturedProcessRequest({
    required this.bytes,
    this.left = 0,
    this.top = 0,
    this.width = 1,
    this.height = 1,
    this.rotateQuarter = 0,
    this.maxSide = 1800,
  });
}

class CapturedProcessResult {
  final Uint8List bytes;
  final int width;
  final int height;
  final double brightness;
  final double sharpness;

  const CapturedProcessResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.brightness,
    required this.sharpness,
  });

  bool get tooDark => brightness < 55;
  bool get blurry => sharpness < 25;
  bool get looksGood => !tooDark && !blurry;

  String get qualityMessage {
    if (tooDark && blurry) {
      return "Rasm qorong'i va xira — chiroqni yoqib qayta oling";
    }
    if (tooDark) return "Rasm qorong'i — chiroqni yoqib qayta oling";
    if (blurry) return 'Rasm xira — telefonni qimirlatmay qayta oling';
    return '✓ Rasm sifati yaxshi';
  }
}

/// Mean luminance (0..255) and Laplacian variance (sharpness) of an image.
({double brightness, double sharpness}) analyzeImageQuality(img.Image source) {
  final small = source.width > 200 ? img.copyResize(source, width: 200) : source;
  final w = small.width;
  final h = small.height;
  if (w < 3 || h < 3) return (brightness: 128.0, sharpness: 100.0);
  final lum = List<double>.filled(w * h, 0);
  var sum = 0.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = small.getPixel(x, y).luminance.toDouble();
      lum[y * w + x] = l;
      sum += l;
    }
  }
  final mean = sum / (w * h);
  var lapSum = 0.0;
  var lapSq = 0.0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final c = lum[y * w + x];
      final lap = 4 * c -
          lum[(y - 1) * w + x] -
          lum[(y + 1) * w + x] -
          lum[y * w + x - 1] -
          lum[y * w + x + 1];
      lapSum += lap;
      lapSq += lap * lap;
      n++;
    }
  }
  final lapMean = n > 0 ? lapSum / n : 0.0;
  final variance = n > 0 ? (lapSq / n) - lapMean * lapMean : 0.0;
  return (brightness: mean, sharpness: variance);
}

/// Decode → fix EXIF → crop to frame → rotate → downscale → quality → JPEG.
/// Top-level so it can run inside `compute`.
CapturedProcessResult processCapturedImage(CapturedProcessRequest r) {
  var image = img.decodeImage(r.bytes);
  if (image == null) {
    throw const FormatException('Rasmni o\'qib bo\'lmadi');
  }
  image = img.bakeOrientation(image);

  final w = image.width;
  final h = image.height;
  final x = (r.left * w).round().clamp(0, w - 1);
  final y = (r.top * h).round().clamp(0, h - 1);
  final cw = (r.width * w).round().clamp(1, w - x);
  final ch = (r.height * h).round().clamp(1, h - y);
  if (x != 0 || y != 0 || cw != w || ch != h) {
    image = img.copyCrop(image, x: x, y: y, width: cw, height: ch);
  }

  final q = r.rotateQuarter % 4;
  if (q != 0) {
    image = img.copyRotate(image, angle: 90.0 * q);
  }

  final longest = math.max(image.width, image.height);
  if (longest > r.maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: r.maxSide)
        : img.copyResize(image, height: r.maxSide);
  }

  final quality = analyzeImageQuality(image);
  final out = Uint8List.fromList(img.encodeJpg(image, quality: 88));
  return CapturedProcessResult(
    bytes: out,
    width: image.width,
    height: image.height,
    brightness: quality.brightness,
    sharpness: quality.sharpness,
  );
}

class RotateRequest {
  final Uint8List bytes;
  final int quarterTurns;

  const RotateRequest(this.bytes, this.quarterTurns);
}

Uint8List rotateJpegQuarter(RotateRequest r) {
  final image = img.decodeImage(r.bytes);
  if (image == null) return r.bytes;
  final rotated = img.copyRotate(image, angle: 90.0 * (r.quarterTurns % 4));
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 88));
}

/// Joins several page photos into one tall image (top to bottom).
Uint8List stitchPagesVertically(List<Uint8List> pages) {
  if (pages.length == 1) return pages.first;
  const targetWidth = 1400;
  final decoded = <img.Image>[];
  for (final p in pages) {
    var im = img.decodeImage(p);
    if (im == null) continue;
    if (im.width != targetWidth) {
      im = img.copyResize(im, width: targetWidth);
    }
    decoded.add(im);
  }
  if (decoded.isEmpty) return pages.first;
  const gap = 12;
  final totalH =
      decoded.fold<int>(0, (a, b) => a + b.height) + gap * (decoded.length - 1);
  final canvas = img.Image(width: targetWidth, height: totalH);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  var y = 0;
  for (final im in decoded) {
    img.compositeImage(canvas, im, dstX: 0, dstY: y);
    y += im.height + gap;
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 88));
}

// ============================================================================
// PUBLIC ENTRY POINT
// ============================================================================

class CustomCameraResult {
  final PickedBytesFile? file;

  /// True when the custom camera could not start (permission denied, no
  /// camera, etc.) so the caller should fall back to the system camera.
  final bool fallbackToSystem;

  const CustomCameraResult({this.file, this.fallbackToSystem = false});
}

Future<CustomCameraResult> openCustomCamera(BuildContext context) async {
  final res = await Navigator.of(context).push<CustomCameraResult>(
    PageRouteBuilder<CustomCameraResult>(
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const CustomCameraScreen(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
  return res ?? const CustomCameraResult();
}

// ============================================================================
// CAMERA SCREEN
// ============================================================================

class CustomCameraScreen extends StatefulWidget {
  const CustomCameraScreen({super.key});

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const int _maxPages = 4;
  static const Color _bg = Color(0xFF0B0A14);

  CameraController? _controller;
  bool _initializing = true;
  FlashMode _flash = FlashMode.off;
  bool _landscapeFrame = false;

  late final AnimationController _scanCtrl;
  late final AnimationController _frameCtrl;
  late final AnimationController _shutterFlashCtrl;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _ax = 0;
  double _ay = 0;
  double _az = 9.8;
  bool _sensorSeen = false;

  final List<Uint8List> _pages = [];
  CapturedProcessResult? _review;
  bool _processing = false;

  Offset? _focusPoint;
  int _focusTick = 0;
  Timer? _focusTimer;

  FrameFractions get _targetFrame =>
      documentFrameFractions(landscape: _landscapeFrame);

  double get _deviation => tiltDeviationDegrees(_ax, _ay, _az);
  TiltLevel get _tiltLevel => tiltLevelFor(_deviation);

  Color get _tiltColor {
    switch (_tiltLevel) {
      case TiltLevel.good:
        return AppTokens.cashGreen;
      case TiltLevel.warn:
        return AppTokens.debtAmber;
      case TiltLevel.bad:
        return AppTokens.dangerRed;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _frameCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _shutterFlashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _startSensors();
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusTimer?.cancel();
    _accelSub?.cancel();
    _scanCtrl.dispose();
    _frameCtrl.dispose();
    _shutterFlashCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  void _startSensors() {
    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen(
        (e) {
          const a = 0.18;
          _ax += (e.x - _ax) * a;
          _ay += (e.y - _ay) * a;
          _az += (e.z - _az) * a;
          _sensorSeen = true;
          if (mounted) setState(() {});
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    setState(() => _initializing = true);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('no camera');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      try {
        await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      try {
        await ctrl.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await ctrl.setFlashMode(_flash);
      } catch (_) {}
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _initializing = false;
      });
    } catch (_) {
      if (mounted) {
        Navigator.of(context)
            .pop(const CustomCameraResult(fallbackToSystem: true));
      }
    }
  }

  Future<void> _cycleFlash() async {
    final c = _controller;
    if (c == null) return;
    const order = [FlashMode.off, FlashMode.auto, FlashMode.torch];
    final next = order[(order.indexOf(_flash) + 1) % order.length];
    HapticFeedback.selectionClick();
    try {
      await c.setFlashMode(next);
      if (mounted) setState(() => _flash = next);
    } catch (_) {}
  }

  void _setFrameLandscape(bool landscape) {
    if (_landscapeFrame == landscape) return;
    HapticFeedback.selectionClick();
    setState(() => _landscapeFrame = landscape);
    if (landscape) {
      _frameCtrl.forward();
    } else {
      _frameCtrl.reverse();
    }
  }

  Future<void> _onTapFocus(TapDownDetails d, Size previewSize) async {
    final c = _controller;
    if (c == null || _review != null) return;
    final p = Offset(
      (d.localPosition.dx / previewSize.width).clamp(0.0, 1.0),
      (d.localPosition.dy / previewSize.height).clamp(0.0, 1.0),
    );
    setState(() {
      _focusPoint = d.localPosition;
      _focusTick++;
    });
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    try {
      await c.setFocusPoint(p);
      await c.setExposurePoint(p);
    } catch (_) {}
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null ||
        !c.value.isInitialized ||
        _processing ||
        c.value.isTakingPicture ||
        _pages.length >= _maxPages) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _processing = true);
    _shutterFlashCtrl.forward(from: 0);
    try {
      final xf = await c.takePicture();
      final bytes = await xf.readAsBytes();
      final f = _targetFrame;
      final res = await compute(
        processCapturedImage,
        CapturedProcessRequest(
          bytes: bytes,
          left: f.left,
          top: f.top,
          width: f.width,
          height: f.height,
        ),
      );
      if (!mounted) return;
      setState(() => _review = res);
    } catch (e) {
      _toast('Suratga olishda xatolik: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_processing || _pages.length >= _maxPages) return;
    setState(() => _processing = true);
    try {
      final xf = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
      );
      if (xf == null) return;
      final bytes = await xf.readAsBytes();
      final res = await compute(
        processCapturedImage,
        CapturedProcessRequest(bytes: bytes),
      );
      if (mounted) setState(() => _review = res);
    } catch (e) {
      _toast('Galereyadan olishda xatolik: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _rotateReview() async {
    final r = _review;
    if (r == null || _processing) return;
    HapticFeedback.selectionClick();
    setState(() => _processing = true);
    try {
      final rotated = await compute(rotateJpegQuarter, RotateRequest(r.bytes, 1));
      if (!mounted) return;
      setState(() {
        _review = CapturedProcessResult(
          bytes: rotated,
          width: r.height,
          height: r.width,
          brightness: r.brightness,
          sharpness: r.sharpness,
        );
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _addReviewAsPage() {
    final r = _review;
    if (r == null) return;
    setState(() {
      _pages.add(r.bytes);
      _review = null;
    });
  }

  Future<void> _finish({bool includeReview = false}) async {
    final all = <Uint8List>[
      ..._pages,
      if (includeReview && _review != null) _review!.bytes,
    ];
    if (all.isEmpty) return;
    setState(() => _processing = true);
    try {
      final bytes = all.length == 1
          ? all.first
          : await compute(stitchPagesVertically, all);
      if (!mounted) return;
      Navigator.of(context).pop(
        CustomCameraResult(
          file: PickedBytesFile(
            bytes: bytes,
            filename: 'nakladnoy_${DateTime.now().millisecondsSinceEpoch}.jpg',
          ),
        ),
      );
    } catch (e) {
      _toast('Rasmlarni birlashtirishda xatolik: $e');
      if (mounted) setState(() => _processing = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _onWillPop() async {
    if (_review != null) {
      setState(() => _review = null);
      return false;
    }
    return true;
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final allow = await _onWillPop();
        if (allow && context.mounted) {
          Navigator.of(context).pop(const CustomCameraResult());
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.9),
                    radius: 1.1,
                    colors: [
                      AppTokens.brandViolet.withValues(alpha: 0.22),
                      _bg,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  _buildTiltChip(),
                  Expanded(child: _buildPreviewArea()),
                  _buildOrientationToggle(),
                  if (_pages.isNotEmpty) _buildPagesStrip(),
                  _buildControls(),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _shutterFlashCtrl,
                  builder: (_, __) => Opacity(
                    opacity: (1 - _shutterFlashCtrl.value) *
                        (_shutterFlashCtrl.isAnimating ? 0.55 : 0),
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),
              ),
            ),
            if (_review != null) Positioned.fill(child: _buildReview()),
          ],
        ),
      ),
    );
  }

  Widget _glassButton({
    required IconData icon,
    required VoidCallback? onTap,
    Color? color,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: TactileScaleTap(
        pressedScale: 0.9,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final flashIcon = switch (_flash) {
      FlashMode.off => Icons.flash_off_rounded,
      FlashMode.auto => Icons.flash_auto_rounded,
      _ => Icons.flash_on_rounded,
    };
    final flashColor = _flash == FlashMode.torch ? AppTokens.debtAmber : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          _glassButton(
            icon: Icons.close_rounded,
            tooltip: 'Yopish',
            onTap: () => Navigator.of(context).pop(const CustomCameraResult()),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Nakladnoy kamerasi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  _pages.isEmpty
                      ? '1-sahifa'
                      : '${_pages.length + 1}-sahifa • $_maxPages tagacha',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _glassButton(
            icon: flashIcon,
            color: flashColor,
            tooltip: 'Chiroq',
            onTap: _cycleFlash,
          ),
        ],
      ),
    );
  }

  Widget _buildTiltChip() {
    final (text, icon) = switch (_tiltLevel) {
      TiltLevel.good => ('Tekis — suratga oling', Icons.check_circle_rounded),
      TiltLevel.warn => ('Telefonni biroz tekislang', Icons.straighten_rounded),
      TiltLevel.bad => (
          "Telefonni qog'ozga parallel tuting",
          Icons.screen_rotation_alt_rounded
        ),
    };
    final color = _sensorSeen ? _tiltColor : Colors.white70;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Container(
          key: ValueKey<String>('${_sensorSeen}_$text'),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                _sensorSeen
                    ? '$text • ${_deviation.toStringAsFixed(0)}°'
                    : "Nakladnoyni ramka ichiga joylang",
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewArea() {
    final c = _controller;
    if (_initializing || c == null || !c.value.isInitialized) {
      return const Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: AppTokens.brandViolet,
          ),
        ),
      );
    }
    final ratio = 1 / c.value.aspectRatio;
    return LayoutBuilder(
      builder: (context, box) {
        var w = box.maxWidth;
        var h = w / ratio;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * ratio;
        }
        final size = Size(w, h);
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              width: w,
              height: h,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _onTapFocus(d, size),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(c),
                    AnimatedBuilder(
                      animation: Listenable.merge([_scanCtrl, _frameCtrl]),
                      builder: (_, __) {
                        final t = Curves.easeOutCubic.transform(_frameCtrl.value);
                        final f =
                            FrameFractions.lerp(kPortraitFrame, kLandscapeFrame, t);
                        return CustomPaint(
                          painter: DocumentFramePainter(
                            frame: f.toRect(size),
                            color: _sensorSeen ? _tiltColor : Colors.white,
                            scanT: _scanCtrl.value,
                          ),
                        );
                      },
                    ),
                    if (_sensorSeen)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: BubbleLevelPainter(
                            offset: Offset(_ax, -_ay) / 9.8,
                            color: _tiltColor,
                          ),
                        ),
                      ),
                    if (_focusPoint != null)
                      Positioned(
                        left: _focusPoint!.dx - 32,
                        top: _focusPoint!.dy - 32,
                        child: IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey<int>(_focusTick),
                            tween: Tween(begin: 1.5, end: 1.0),
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutBack,
                            builder: (_, s, __) => Transform.scale(
                              scale: s,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTokens.brandViolet,
                                    width: 2.4,
                                  ),
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
          ),
        );
      },
    );
  }

  Widget _buildOrientationToggle() {
    Widget pill(String label, IconData icon, bool selected, bool landscape) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _setFrameLandscape(landscape),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: selected ? AppTokens.aiGradient : null,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 17, color: selected ? Colors.white : Colors.white60),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(70, 8, 70, 4),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            pill('Tik', Icons.crop_portrait_rounded, !_landscapeFrame, false),
            pill('Yotiq', Icons.crop_landscape_rounded, _landscapeFrame, true),
          ],
        ),
      ),
    );
  }

  Widget _buildPagesStrip() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: _pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _pages[i],
                width: 46,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: InkWell(
                onTap: () => setState(() => _pages.removeAt(i)),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: AppTokens.dangerRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 12, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              bottom: 2,
              left: 4,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final canShoot = !_processing && _pages.length < _maxPages;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 56,
            child: _glassButton(
              icon: Icons.photo_library_rounded,
              tooltip: 'Galereya',
              onTap: canShoot ? _pickFromGallery : null,
            ),
          ),
          TactileScaleTap(
            pressedScale: 0.92,
            child: GestureDetector(
              onTap: canShoot ? _capture : null,
              child: Container(
                width: 82,
                height: 82,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: AppTokens.brandViolet.withValues(alpha: 0.5),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: canShoot ? AppTokens.aiGradient : null,
                    color: canShoot ? null : Colors.white24,
                  ),
                  child: _processing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: _pages.isNotEmpty
                ? TactileScaleTap(
                    pressedScale: 0.92,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _processing ? null : () => _finish(),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTokens.cashGreen,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.check_rounded,
                                color: Colors.white, size: 28),
                            Positioned(
                              top: 4,
                              right: 6,
                              child: Text(
                                '${_pages.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildReview() {
    final r = _review!;
    final qColor = r.looksGood ? AppTokens.cashGreen : AppTokens.debtAmber;
    final canAddMore = _pages.length + 1 < _maxPages;
    return Container(
      color: _bg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ko\'rib chiqish',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _glassButton(
                    icon: Icons.rotate_90_degrees_cw_rounded,
                    tooltip: "90° burish",
                    onTap: _processing ? null : _rotateReview,
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: qColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: qColor.withValues(alpha: 0.55)),
              ),
              child: Row(
                children: [
                  Icon(
                    r.looksGood
                        ? Icons.verified_rounded
                        : Icons.warning_amber_rounded,
                    color: qColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.qualityMessage,
                      style: TextStyle(
                        color: qColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.memory(r.bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed:
                          _processing ? null : () => setState(() => _review = null),
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: const Text('Qayta'),
                    ),
                  ),
                  if (canAddMore) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                        ),
                        onPressed: _processing ? null : _addReviewAsPage,
                        icon: const Icon(Icons.add_photo_alternate_rounded,
                            size: 18),
                        label: const Text('Sahifa'),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.cashGreen,
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed: _processing
                          ? null
                          : () => _finish(includeReview: true),
                      icon: _processing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _pages.isEmpty
                            ? 'Ishlatish'
                            : 'Tayyor (${_pages.length + 1})',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PAINTERS
// ============================================================================

class DocumentFramePainter extends CustomPainter {
  final Rect frame;
  final Color color;
  final double scanT;

  const DocumentFramePainter({
    required this.frame,
    required this.color,
    required this.scanT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 18.0;
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(radius));

    // Dim everything outside the frame.
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );

    // Faint full border.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.28),
    );

    // Corner brackets (glow + solid).
    const len = 32.0;
    final l = frame.left;
    final t = frame.top;
    final r = frame.right;
    final b = frame.bottom;
    const rd = radius;
    final corners = Path()
      ..moveTo(l, t + len)
      ..lineTo(l, t + rd)
      ..arcTo(Rect.fromLTWH(l, t, rd * 2, rd * 2), math.pi, math.pi / 2, false)
      ..lineTo(l + len, t)
      ..moveTo(r - len, t)
      ..lineTo(r - rd, t)
      ..arcTo(Rect.fromLTWH(r - rd * 2, t, rd * 2, rd * 2), -math.pi / 2,
          math.pi / 2, false)
      ..lineTo(r, t + len)
      ..moveTo(r, b - len)
      ..lineTo(r, b - rd)
      ..arcTo(Rect.fromLTWH(r - rd * 2, b - rd * 2, rd * 2, rd * 2), 0,
          math.pi / 2, false)
      ..lineTo(r - len, b)
      ..moveTo(l + len, b)
      ..lineTo(l + rd, b)
      ..arcTo(Rect.fromLTWH(l, b - rd * 2, rd * 2, rd * 2), math.pi / 2,
          math.pi / 2, false)
      ..lineTo(l, b - len);

    canvas.drawPath(
      corners,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      corners,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    // Soft scanning line.
    final y = frame.top + frame.height * scanT;
    final inset = 16.0;
    final lineRect = Rect.fromLTWH(
        frame.left + inset, y - 1.5, frame.width - inset * 2, 3);
    canvas.drawRect(
      lineRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.85),
            color.withValues(alpha: 0),
          ],
        ).createShader(lineRect),
    );
  }

  @override
  bool shouldRepaint(covariant DocumentFramePainter old) =>
      old.frame != frame || old.color != color || old.scanT != scanT;
}

class BubbleLevelPainter extends CustomPainter {
  /// Normalised tilt (-1..1 per axis, roughly accel/g).
  final Offset offset;
  final Color color;

  const BubbleLevelPainter({required this.offset, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const ringR = 24.0;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawCircle(c, ringR, ring);
    canvas.drawLine(c.translate(-ringR - 6, 0), c.translate(-ringR + 8, 0), ring);
    canvas.drawLine(c.translate(ringR - 8, 0), c.translate(ringR + 6, 0), ring);
    canvas.drawLine(c.translate(0, -ringR - 6), c.translate(0, -ringR + 8), ring);
    canvas.drawLine(c.translate(0, ringR - 8), c.translate(0, ringR + 6), ring);

    var dx = offset.dx * 70;
    var dy = offset.dy * 70;
    final dist = math.sqrt(dx * dx + dy * dy);
    const maxD = ringR + 14;
    if (dist > maxD) {
      dx = dx / dist * maxD;
      dy = dy / dist * maxD;
    }
    canvas.drawCircle(
      c.translate(dx, dy),
      7,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(c.translate(dx, dy), 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant BubbleLevelPainter old) =>
      old.offset != offset || old.color != color;
}
