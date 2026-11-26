import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisobchi_app/api_client.dart';
import 'package:hisobchi_app/custom_camera.dart';
import 'package:hisobchi_app/main.dart';
import 'package:hisobchi_app/offline_sync.dart';
import 'package:hisobchi_app/security.dart';
import 'package:hisobchi_app/theme.dart';
import 'package:hisobchi_app/widgets.dart';
import 'package:hisobchi_app/widgets_3d.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('formatUzs and parseUzsInput handle Uzbek amounts properly', () {
    expect(formatUzs(1554000, withCurrency: true), "1 554 000 so'm");
    expect(formatUzs(0), '0');
    expect(parseUzsInput('1 554 000'), 1554000);
    expect(parseUzsInput('260000'), 260000);
    expect(UzsAmountInputFormatter.formatDigits('1554000'), '1 554 000');
  });

  test('findLocalSimilarSuppliers matches Cyrillic and cursive Ittin to Ummun',
      () {
    final suppliers = ['Coca Cola', 'Ummun', 'ISMAT KEPAK NON', 'Non Oka'];
    final fromCyr = findLocalSimilarSuppliers('Иттин', suppliers);
    expect(fromCyr, contains('Ummun'));
    expect(fromCyr.first, 'Ummun');

    final fromLat = findLocalSimilarSuppliers('Ittin', suppliers);
    expect(fromLat.first, 'Ummun');

    final fromPhonetic = findLocalSimilarSuppliers('Уммун', suppliers);
    expect(fromPhonetic.first, 'Ummun');
  });

  testWidgets('LoginScreen renders instructions and 8-digit code input',
      (WidgetTester tester) async {
    final api = HisobchiApiClient(baseUrl: 'https://hisobchi.domen.uz');
    await tester.pumpWidget(HisobchiApp(apiOverride: api));
    await tester.pumpAndSettle();

    expect(find.text('Hisobchi Mobil'), findsOneWidget);
    expect(find.text('Ilovaga kirish'), findsOneWidget);
    expect(find.text('Telegramdan parol (kod) olish'), findsOneWidget);
    expect(find.byIcon(Icons.content_paste_rounded), findsOneWidget);
    expect(find.textContaining('8 xonali kirish kodi'), findsOneWidget);
  });

  testWidgets('sheetMaxHeight adapts cleanly for 3-button bar, full screen, and keyboard',
      (WidgetTester tester) async {
    Future<double> measureWith({
      required Size size,
      required EdgeInsets viewPadding,
      EdgeInsets viewInsets = EdgeInsets.zero,
      double fraction = 0.92,
    }) async {
      late double result;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              viewPadding: viewPadding,
              padding: viewPadding,
              viewInsets: viewInsets,
            ),
            child: Builder(
              builder: (ctx) {
                result = sheetMaxHeight(ctx, fraction: fraction);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return result;
    }

    const screenSize = Size(400, 800);
    // 1. Phone WITH 3-button Android home bar (48dp bottom viewPadding)
    final withHomeBar = await measureWith(
      size: screenSize,
      viewPadding: const EdgeInsets.only(top: 28, bottom: 48),
    );
    expect(withHomeBar, lessThanOrEqualTo(676.0));
    expect(withHomeBar, equals(676.0));

    // 2. Phone WITHOUT bottom bar (0dp bottom viewPadding)
    final withoutBar = await measureWith(
      size: screenSize,
      viewPadding: const EdgeInsets.only(top: 28, bottom: 0),
    );
    expect(withoutBar, lessThanOrEqualTo(724.0));
    expect(withoutBar - withHomeBar, equals(48.0));

    // 3. Soft keyboard open (300dp viewInsets.bottom) shrinks height safely
    final withKeyboard = await measureWith(
      size: screenSize,
      viewPadding: const EdgeInsets.only(top: 28, bottom: 48),
      viewInsets: const EdgeInsets.only(bottom: 300),
    );
    expect(withKeyboard, equals(376.0));
    expect(withKeyboard, lessThan(withHomeBar));
  });

  testWidgets('HisobchiAnimatedLoadingScreen and DashboardLoadingSkeleton render cleanly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: const Scaffold(
          body: HisobchiAnimatedLoadingScreen(
            subtitle: 'Ilova tayyorlanmoqda...',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hisobchi'), findsOneWidget);
    expect(find.text('Ilova tayyorlanmoqda...'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: const Scaffold(body: DashboardLoadingSkeleton()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DashboardLoadingSkeleton), findsOneWidget);
  });

  testWidgets('TactileScaleTap and showActionFeedbackBanner animate cleanly',
      (WidgetTester tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (ctx) => TactileScaleTap(
                pressedScale: 0.92,
                child: FilledButton(
                  onPressed: () {
                    tapped = true;
                    showActionFeedbackBanner(ctx, 'Saqlandi!');
                  },
                  child: const Text('Bosing'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Bosing')),
    );
    await tester.pump(const Duration(milliseconds: 90));
    final pressedScaleWidget = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(TactileScaleTap),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(pressedScaleWidget.scale, equals(0.92));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(tapped, isTrue);
    expect(find.text('Saqlandi!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Saqlandi!'), findsNothing);
  });

  testWidgets('AnimatedUzsNumber rolls upward from 1 and re-rolls on animSeed change',
      (WidgetTester tester) async {
    var seed = 0;
    late StateSetter hostSetState;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                hostSetState = setState;
                return AnimatedUzsNumber(
                  value: 150000,
                  withCurrency: true,
                  animSeed: seed,
                  duration: const Duration(milliseconds: 500),
                );
              },
            ),
          ),
        ),
      ),
    );

    // Frame 0 starts at 1 so'm
    expect(find.text("1 so'm"), findsOneWidget);

    // Midway should be strictly between 1 and 150 000
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text("1 so'm"), findsNothing);
    expect(find.text("150 000 so'm"), findsNothing);

    // Settled reaches full 150 000 so'm
    await tester.pumpAndSettle();
    expect(find.text("150 000 so'm"), findsOneWidget);

    // Incrementing animSeed replays the upward count even with identical value
    hostSetState(() => seed = 1);
    await tester.pump();
    expect(find.text("1 so'm"), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text("150 000 so'm"), findsOneWidget);
  });

  testWidgets('PinLockScreen handles 2-step setup, mismatch, 1-step unlock, and PIN change',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.reset());

    Future<void> enterDigits(String digits) async {
      for (final ch in digits.split('')) {
        await tester.tap(find.text(ch).last);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
    }

    String? completedPin;
    bool? completedBio;

    // 1. Setup mode: requires entering PIN twice (mismatch resets back to step 1)
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: PinLockScreen(
          key: const ValueKey('test_pin_setup'),
          mode: PinScreenMode.setup,
          onCanUseBiometric: () async => false,
          onCompleted: (pin, bio) async {
            completedPin = pin;
            completedBio = bio;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("PIN kod o'rnating"), findsOneWidget);

    await enterDigits('1234');
    expect(find.text('PIN kodni tasdiqlang'), findsOneWidget);

    // Wrong 2nd entry shows error and resets to step 1 without completing
    await enterDigits('9999');
    expect(find.text("PIN kodlar mos kelmadi. Boshidan kiriting."), findsOneWidget);
    expect(find.text("PIN kod o'rnating"), findsOneWidget);
    expect(completedPin, isNull);

    // Matching 2nd entry saves PIN
    await enterDigits('1234');
    expect(find.text('PIN kodni tasdiqlang'), findsOneWidget);
    await enterDigits('1234');
    expect(completedPin, equals('1234'));
    expect(completedBio, isFalse);

    // 2. Unlock mode: unlocks in 1 step
    completedPin = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: PinLockScreen(
          key: const ValueKey('test_pin_unlock'),
          mode: PinScreenMode.unlock,
          expectedPin: '1234',
          biometricEnabled: false,
          onCanUseBiometric: () async => false,
          onCompleted: (pin, bio) async {
            completedPin = pin;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterDigits('0000');
    expect(completedPin, isNull);
    await enterDigits('1234');
    expect(completedPin, equals('1234'));

    // 3. Change mode: verifies old PIN, then new PIN twice
    completedPin = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: PinLockScreen(
          key: const ValueKey('test_pin_change'),
          mode: PinScreenMode.change,
          expectedPin: '1234',
          onCanUseBiometric: () async => false,
          onCompleted: (pin, bio) async {
            completedPin = pin;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Joriy PIN kod'), findsOneWidget);

    await enterDigits('1234');
    expect(find.text("PIN kod o'rnating"), findsOneWidget);
    await enterDigits('4321');
    expect(find.text('PIN kodni tasdiqlang'), findsOneWidget);
    await enterDigits('4321');
    expect(completedPin, equals('4321'));
  });

  test('computeSupplierAnomalyWarning flags abnormal spikes and ignores normal amounts',
      () {
    expect(computeSupplierAnomalyWarning(450000, [400000, 420000]), isNull);
    final warn = computeSupplierAnomalyWarning(1200000, [380000, 420000]);
    expect(warn, isNotNull);
    expect(warn, contains('+200%'));
  });

  test('OfflineOutboxStore queues offline writes and flushes FIFO when online',
      () async {
    SharedPreferences.setMockInitialValues({});
    await OfflineOutboxStore.clearAll();

    await OfflineOutboxStore.enqueueCash(
      amount: 500000,
      sourceType: 'main',
      note: 'Oflayn kirim',
    );
    await OfflineOutboxStore.enqueueNakladnoy(
      supplierName: 'Coca Cola',
      amount: 320000,
      paymentMode: 'cash',
    );
    expect(await OfflineOutboxStore.count(), equals(2));

    final hitPaths = <String>[];
    final mockHttp = MockClient((req) async {
      hitPaths.add(req.url.path);
      if (req.url.path == '/cash') {
        return http.Response(
          jsonEncode({
            'id': 1,
            'session_id': 1,
            'amount': 500000,
            'source_type': 'main',
            'note': 'Oflayn kirim',
            'created_at': '2026-11-24 12:00',
            'time_hm': '12:00',
          }),
          200,
        );
      }
      if (req.url.path == '/nakladnoy') {
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      return http.Response('Not found', 404);
    });

    final api = HisobchiApiClient(
      baseUrl: 'https://hisobchi.domen.uz',
      accessToken: 'test-token',
      httpClient: mockHttp,
    );
    final res = await OfflineOutboxStore.flushAll(api);
    expect(res.sent, equals(2));
    expect(res.remaining, equals(0));
    expect(hitPaths, equals(['/cash', '/nakladnoy']));
    expect(await OfflineOutboxStore.count(), equals(0));
  });

  testWidgets('SwipeableNakladnoyTile triggers quickPay and duplicate without dismissing',
      (WidgetTester tester) async {
    var paid = 0;
    var duplicated = 0;
    const item = NakladnoyItem(
      id: 42,
      sessionId: 1,
      displayNum: '#42',
      supplierName: 'Coca Cola',
      amount: 450000,
      paymentMethod: 'cash',
      isDebt: true,
      note: '',
      hasPhoto: false,
      inGroup: true,
      createdAt: '2026-11-20 10:00',
      timeHm: '10:00',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SwipeableNakladnoyTile(
              item: item,
              onTap: () {},
              onQuickPay: () => paid++,
              onDuplicate: () => duplicated++,
            ),
          ),
        ),
      ),
    );

    // Swipe right -> Quick pay
    await tester.drag(find.byType(SwipeableNakladnoyTile), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(paid, equals(1));
    expect(find.text('Coca Cola'), findsOneWidget);

    // Swipe left -> Duplicate
    await tester.drag(
        find.byType(SwipeableNakladnoyTile), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(duplicated, equals(1));
    expect(find.text('Coca Cola'), findsOneWidget);
  });

  test('Session time spans and multi-smena / 24h date matching format accurately',
      () {
    expect(
      formatSessionTimeSpan(
        reportDate: '2026-11-24',
        status: 'closed',
        openedAt: '2026-11-24 08:30',
        closedAt: '2026-11-24 20:00',
      ),
      equals('08:30–20:00'),
    );
    expect(
      formatSessionTimeSpan(
        reportDate: '2026-11-24',
        status: 'open',
        openedAt: '2026-11-24 20:25',
        closedAt: '',
      ),
      equals('20:25 dan ochiq'),
    );
    expect(
      formatSessionTimeSpan(
        reportDate: '2026-11-23',
        status: 'closed',
        openedAt: '2026-11-23 09:00',
        closedAt: '2026-11-24 14:15',
      ),
      equals('11-23 09:00 → 11-24 14:15'),
    );

    const sutkaSession = HistorySessionItem(
      id: 15,
      reportDate: '2026-11-23',
      status: 'closed',
      openingBalance: 0,
      expectedCash: 500000,
      createdAt: '2026-11-23 09:00',
      closedAt: '2026-11-24 14:15',
      shiftSeq: 2,
      shiftTotal: 2,
    );
    expect(sutkaSession.shiftBadge, equals('2-smena (#15)'));
    expect(sutkaSession.matchesDate('2026-11-23'), isTrue);
    expect(sutkaSession.matchesDate('2026-11-24'), isTrue);
    expect(sutkaSession.matchesDate('2026-11-25'), isFalse);
  });

  test('Camera tilt level: flat is good, slightly tilted warns, steep is bad', () {
    expect(tiltDeviationDegrees(0, 0, 9.8), closeTo(0, 0.01));
    expect(tiltLevelFor(tiltDeviationDegrees(0, 0, 9.8)), TiltLevel.good);
    expect(tiltLevelFor(tiltDeviationDegrees(0, 1.0, 9.76)), TiltLevel.warn);
    expect(tiltLevelFor(tiltDeviationDegrees(0, 2.5, 9.5)), TiltLevel.bad);
    // Upright phone (sheet on a wall) also counts as aligned.
    expect(tiltDeviationDegrees(0, 9.8, 0), closeTo(0, 0.01));
  });

  test('Document frame fractions: landscape frame is wide, portrait is tall', () {
    final p = documentFrameFractions(landscape: false);
    final l = documentFrameFractions(landscape: true);
    const preview = Size(300, 400);
    final pr = p.toRect(preview);
    final lr = l.toRect(preview);
    expect(pr.height, greaterThan(pr.width));
    expect(lr.width, greaterThan(lr.height));
    final mid = FrameFractions.lerp(kPortraitFrame, kLandscapeFrame, 0.5);
    expect(mid.width, closeTo((p.width + l.width) / 2, 1e-9));
  });

  test('processCapturedImage crops to frame, rotates, and flags quality', () {
    final flat = img.Image(width: 400, height: 600);
    img.fill(flat, color: img.ColorRgb8(235, 235, 235));
    final flatJpg = Uint8List.fromList(img.encodeJpg(flat, quality: 90));

    final cropped = processCapturedImage(
      CapturedProcessRequest(
        bytes: flatJpg,
        left: 0.1,
        top: 0.1,
        width: 0.5,
        height: 0.5,
      ),
    );
    expect(cropped.width, 200);
    expect(cropped.height, 300);
    expect(cropped.tooDark, isFalse);
    expect(cropped.blurry, isTrue); // perfectly flat image has no detail

    final rotated = processCapturedImage(
      CapturedProcessRequest(bytes: flatJpg, rotateQuarter: 1),
    );
    expect(rotated.width, 600);
    expect(rotated.height, 400);

    final dark = img.Image(width: 200, height: 200);
    img.fill(dark, color: img.ColorRgb8(10, 10, 10));
    final darkRes = processCapturedImage(
      CapturedProcessRequest(
        bytes: Uint8List.fromList(img.encodeJpg(dark, quality: 90)),
      ),
    );
    expect(darkRes.tooDark, isTrue);
    expect(darkRes.qualityMessage, contains("qorong'i"));

    // Sharp checkerboard is not blurry.
    final sharp = img.Image(width: 240, height: 240);
    for (var y = 0; y < 240; y++) {
      for (var x = 0; x < 240; x++) {
        final on = ((x ~/ 6) + (y ~/ 6)) % 2 == 0;
        sharp.setPixelRgb(x, y, on ? 240 : 20, on ? 240 : 20, on ? 240 : 20);
      }
    }
    final sharpRes = processCapturedImage(
      CapturedProcessRequest(
        bytes: Uint8List.fromList(img.encodeJpg(sharp, quality: 95)),
      ),
    );
    expect(sharpRes.blurry, isFalse);
  });

  test('stitchPagesVertically joins pages into one tall image', () {
    Uint8List page(int w, int h, int shade) {
      final im = img.Image(width: w, height: h);
      img.fill(im, color: img.ColorRgb8(shade, shade, shade));
      return Uint8List.fromList(img.encodeJpg(im, quality: 90));
    }

    final single = page(300, 400, 200);
    expect(stitchPagesVertically([single]), same(single));

    final joined = stitchPagesVertically([page(700, 900, 220), page(700, 900, 180)]);
    final decoded = img.decodeImage(joined)!;
    expect(decoded.width, 1400);
    expect(decoded.height, greaterThan(2 * 1800));
  });

  test('SyncVersionInfo, shouldTriggerRemoteSync, and SyncBus work cleanly', () {
    expect(shouldTriggerRemoteSync(null, 'a:2'), isFalse);
    expect(shouldTriggerRemoteSync('', 'a:2'), isFalse);
    expect(shouldTriggerRemoteSync('a:2', ''), isFalse);
    expect(shouldTriggerRemoteSync('a:2', 'a:2'), isFalse);
    expect(shouldTriggerRemoteSync('a:2', 'a:3'), isTrue);
    expect(shouldTriggerRemoteSync('a:2', 'b:1'), isTrue);

    final info = SyncVersionInfo.fromJson({
      'rev': 'boot1:42',
      'seq': 42,
      'last_event': 'nakladnoy_payments',
      'updated_at': '2026-11-25T10:30:00Z',
      'apk_version': '1.0.30',
      'apk_build': 30,
      'web_version': '123456-789',
    });
    expect(info.rev, 'boot1:42');
    expect(info.seq, 42);
    expect(info.lastEvent, 'nakladnoy_payments');
    expect(info.apkVersion, '1.0.30');
    expect(info.apkBuild, 30);
    expect(info.webVersion, '123456-789');

    var ticks = 0;
    void listener() => ticks++;
    SyncBus.remoteChangeTick.addListener(listener);
    try {
      SyncBus.notifyRemoteChange();
      SyncBus.notifyRemoteChange();
      expect(ticks, equals(2));
    } finally {
      SyncBus.remoteChangeTick.removeListener(listener);
    }
  });

  testWidgets(
      '3D cube math projects 6 depth-sorted faces and Interactive3DFintechCube handles drag & tap',
      (WidgetTester tester) async {
    final faces = computeCubeFaces(0.5, 0.7, 0.1, const Size(200, 200));
    expect(faces.length, equals(6));
    for (var i = 1; i < faces.length; i++) {
      expect(faces[i].avgZ, greaterThanOrEqualTo(faces[i - 1].avgZ));
    }
    for (final f in faces) {
      expect(f.points.length, equals(4));
      expect(f.light, inInclusiveRange(0.0, 1.0));
    }

    var started = 0;
    var ended = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: Interactive3DFintechCube(
              size: 160,
              continuousSpin: false,
              onInteractStart: () => started++,
              onInteractEnd: () => ended++,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.drag(find.byType(Interactive3DFintechCube), const Offset(55, -25));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(Interactive3DFintechCube));
    await tester.pump(const Duration(milliseconds: 50));
    // Settle intro & inertia cleanly
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(started, greaterThanOrEqualTo(2));
    expect(ended, greaterThanOrEqualTo(2));
  });

  test('hasNakladnoyEdits and buildNakladnoyEditSummary detect changes accurately',
      () {
    expect(
      hasNakladnoyEdits(
        originalSupplier: 'Coca Cola',
        originalAmount: 450000,
        originalNote: 'naqd',
        currentSupplier: 'Coca Cola',
        currentAmountText: '450 000',
        currentNote: 'naqd',
      ),
      isFalse,
    );
    expect(
      hasNakladnoyEdits(
        originalSupplier: 'Coca Cola',
        originalAmount: 450000,
        originalNote: '',
        currentSupplier: 'Pepsi',
        currentAmountText: '450 000',
        currentNote: '',
      ),
      isTrue,
    );
    expect(
      hasNakladnoyEdits(
        originalSupplier: 'Coca Cola',
        originalAmount: 450000,
        originalNote: '',
        currentSupplier: 'Coca Cola',
        currentAmountText: '500 000',
        currentNote: '',
      ),
      isTrue,
    );

    final summary = buildNakladnoyEditSummary(
      oldSupplier: 'Coca Cola',
      oldAmount: 450000,
      oldNote: '',
      newSupplier: 'Pepsi',
      newAmount: 500000,
      newNote: 'chek bor',
    );
    expect(summary, contains('Coca Cola → Pepsi'));
    expect(summary, contains('450 000'));
    expect(summary, contains('500 000'));
    expect(summary, contains('Izoh: chek bor'));
  });

  testWidgets(
      'showTopSlideNotification slides in at top overlay and renders title & subtitle',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showTopSlideNotification(
                    ctx,
                    title: "Nakladnoy o'zgartirildi",
                    subtitle: "Coca Cola • 450 000 → 500 000 so'm",
                    tone: TopNotifyTone.edit,
                    duration: const Duration(milliseconds: 900),
                  );
                },
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trigger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text("Nakladnoy o'zgartirildi"), findsOneWidget);
    expect(find.text("Coca Cola • 450 000 → 500 000 so'm"), findsOneWidget);

    // Wait for auto-dismiss timer + reverse animation to finish cleanly
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text("Nakladnoy o'zgartirildi"), findsNothing);
  });

  testWidgets(
      'Hisobchi3DWelcomeScreen plays 3.2s cosmic 3D squircle splash then enters',
      (WidgetTester tester) async {
    var continued = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Hisobchi3DWelcomeScreen(
          onContinue: () => continued++,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HisobchiSplash), findsOneWidget);
    expect(continued, equals(0));

    // Still animating at 2.5s
    await tester.pump(const Duration(milliseconds: 2000));
    expect(continued, equals(0));

    // Completes cleanly at ~3.2s
    await tester.pump(const Duration(milliseconds: 900));
    expect(continued, equals(1));
  });

  testWidgets(
      'HeroBalanceCard renders Pul oldim and Xarajat buttons without Egadan',
      (WidgetTester tester) async {
    final summary = StatusSummary.fromJson({
      'session_id': 1,
      'report_date': '2026-11-25',
      'session_status': 'open',
      'opened_at': '2026-11-25 09:00',
      'closed_at': '',
      'opening_balance': 200000,
      'main_cash_in': 1000000,
      'kassa_debt_today': 0,
      'kassa_repay_today': 0,
      'expense_today': 75000,
      'total_available_inflow': 1200000,
      'total_nakladnoy_spent': 300000,
      'total_card_spent': 0,
      'total_transfer_spent': 0,
      'total_debt_nakladnoy': 0,
      'expected_cash': 825000,
      'total_kassa_debt_outstanding': 0,
      'all_unpaid_debt_count': 0,
      'all_unpaid_debt_total': 0,
      'group_info': {'bound': true, 'chat_id': -1001, 'title': 'Guruh'},
      'cash_transactions': [],
      'nakladnoys': [],
    });
    expect(summary.expenseToday, equals(75000));

    var pulOldimTapped = 0;
    var xarajatTapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: HeroBalanceCard(
                summary: summary,
                onAddCash: () => pulOldimTapped++,
                onExpense: () => xarajatTapped++,
                onKassaDebt: () {},
                onKassaRepay: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Egadan'), findsNothing);
    expect(find.text('Egadan oldim'), findsNothing);
    expect(find.text('Pul oldim'), findsNWidgets(2)); // Sub-stat + action button
    expect(find.text('Xarajat'), findsNWidgets(2)); // Sub-stat + action button

    await tester.tap(find.widgetWithIcon(InkWell, Icons.trending_down_rounded));
    await tester.pump();
    expect(xarajatTapped, equals(1));

    await tester.tap(find.widgetWithIcon(InkWell, Icons.add_card_rounded));
    await tester.pump();
    expect(pulOldimTapped, equals(1));
  });

  testWidgets(
      'Flagship HisobchiSplash renders 3D depth, shimmer title, and drag/tap',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: const HisobchiSplash(
          title: 'Hisobchi',
          subtitle: 'Tayyorlanmoqda...',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Hisobchi'), findsOneWidget);
    expect(find.text('Tayyorlanmoqda...'), findsOneWidget);

    // Interactive drag & tap on 3D splash emblem should not throw
    await tester.drag(find.byType(HisobchiSplash), const Offset(30, -20));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(HisobchiSplash));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets(
      'FloatingGlassBottomNav renders 4 tabs, badges, and switches index on tap',
      (WidgetTester tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            extendBody: true,
            body: const SizedBox.expand(),
            bottomNavigationBar: FloatingGlassBottomNav(
              selectedIndex: selected,
              onDestinationSelected: (i) => setState(() => selected = i),
              destinations: const [
                FloatingNavDestination(
                  icon: Icons.space_dashboard_outlined,
                  selectedIcon: Icons.space_dashboard_rounded,
                  label: 'Dashboard',
                ),
                FloatingNavDestination(
                  icon: Icons.receipt_long_outlined,
                  selectedIcon: Icons.receipt_long_rounded,
                  label: 'Amallar',
                  badgeCount: 5,
                ),
                FloatingNavDestination(
                  icon: Icons.storefront_outlined,
                  selectedIcon: Icons.storefront_rounded,
                  label: "Ta'minotchilar",
                  badgeCount: 12,
                ),
                FloatingNavDestination(
                  icon: Icons.assessment_outlined,
                  selectedIcon: Icons.assessment_rounded,
                  label: 'Smena',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Amallar'), findsOneWidget);
    expect(find.text("Ta'minotchilar"), findsOneWidget);
    expect(find.text('Smena'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await tester.tap(find.text("Ta'minotchilar"));
    await tester.pumpAndSettle();
    expect(selected, equals(2));

    await tester.tap(find.text('Smena'));
    await tester.pumpAndSettle();
    expect(selected, equals(3));
  });

  testWidgets(
      'DashboardAnalyticsSection renders glowing distribution, neon KPI cards, and bar/line chart toggle',
      (WidgetTester tester) async {
    final summary = StatusSummary.fromJson({
      'session_id': 10,
      'report_date': '2026-11-26',
      'session_status': 'open',
      'opened_at': '2026-11-26 08:30',
      'closed_at': '',
      'opening_balance': 500000,
      'main_cash_in': 2000000,
      'kassa_debt_today': 0,
      'kassa_repay_today': 0,
      'expense_today': 50000,
      'total_available_inflow': 2500000,
      'total_nakladnoy_spent': 950000,
      'total_card_spent': 300000,
      'total_transfer_spent': 200000,
      'total_debt_nakladnoy': 150000,
      'expected_cash': 1500000,
      'total_kassa_debt_outstanding': 0,
      'all_unpaid_debt_count': 1,
      'all_unpaid_debt_total': 150000,
      'group_info': {'bound': true, 'chat_id': -1001, 'title': 'Guruh'},
      'cash_transactions': [],
      'nakladnoys': [
        {
          'id': 1,
          'session_id': 10,
          'display_num': '#1',
          'supplier_name': 'Coca Cola',
          'amount': 950000,
          'payment_method': 'cash',
          'is_debt': false,
          'note': '',
          'has_photo': false,
          'in_group': true,
          'created_at': '2026-11-26 10:00',
          'time_hm': '10:00',
        },
        {
          'id': 2,
          'session_id': 10,
          'display_num': '#2',
          'supplier_name': 'Pepsi',
          'amount': 300000,
          'payment_method': 'card',
          'is_debt': false,
          'note': '',
          'has_photo': false,
          'in_group': true,
          'created_at': '2026-11-26 11:00',
          'time_hm': '11:00',
        },
      ],
    });

    final series = [
      {'date': '2026-11-24', 'label': '24-noy', 'spent': 400000, 'cash_in': 600000, 'count': 2},
      {'date': '2026-11-25', 'label': '25-noy', 'spent': 750000, 'cash_in': 1000000, 'count': 3},
      {'date': '2026-11-26', 'label': '26-noy', 'spent': 950000, 'cash_in': 2000000, 'count': 2},
    ];

    String? tappedFilter;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DashboardAnalyticsSection(
              summary: summary,
              canWrite: true,
              dailySeries: series,
              onSelectPeriodKey: (_) {},
              onPickCustomDateRange: () {},
              onTapPaymentFilter: (mode) => tappedFilter = mode,
              onOpenNakladnoyTab: () {},
              onTapNakladnoy: (_) {},
              onEditCashTx: (_) {},
              onDeleteCashTx: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Xarajatlar taqsimoti'), findsOneWidget);
    expect(find.text('Ustun'), findsOneWidget);
    expect(find.text('Chiziq'), findsOneWidget);
    expect(find.text("NAQD TO'LOV"), findsOneWidget);

    // Toggle to smooth line chart mode and back without issues
    await tester.tap(find.text('Chiziq'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustun'));
    await tester.pumpAndSettle();

    // Tapping KPI card triggers payment filter callback
    await tester.ensureVisible(find.text("NAQD TO'LOV"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("NAQD TO'LOV"));
    await tester.pump();
    expect(tappedFilter, equals('cash'));
  });

  test('CashReconciliationItem parses interim and closing sverka records accurately',
      () {
    final interim = CashReconciliationItem.fromJson({
      'id': 7,
      'session_id': 12,
      'report_date': '2026-11-26',
      'kind': 'interim',
      'expected_cash': 1500000,
      'counted_cash': 1480000,
      'difference': -20000,
      'note': 'Tushlik sverkasi',
      'created_at': '2026-11-26 14:10',
      'time_hm': '14:10',
    });
    expect(interim.id, equals(7));
    expect(interim.isClosing, isFalse);
    expect(interim.expectedCash, equals(1500000));
    expect(interim.countedCash, equals(1480000));
    expect(interim.difference, equals(-20000));
    expect(interim.timeHm, equals('14:10'));
    expect(interim.note, equals('Tushlik sverkasi'));

    final closing = CashReconciliationItem.fromJson({
      'id': 8,
      'session_id': 12,
      'report_date': '2026-11-26',
      'kind': 'closing',
      'expected_cash': 1500000,
      'counted_cash': 1505000,
      'difference': 5000,
      'note': 'Kechki yopish',
      'created_at': '2026-11-26 21:00',
      'time_hm': '21:00',
    });
    expect(closing.isClosing, isTrue);
    expect(closing.difference, equals(5000));
    expect(closing.timeHm, equals('21:00'));
  });

  testWidgets(
      'Hisobchi3DEmblem renders 3D glossy emblem and settles cleanly after drag & tap',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: const Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: HisobchiBottomHorizonArc()),
              Center(child: Hisobchi3DEmblem(size: 120)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Hisobchi3DEmblem), findsOneWidget);
    expect(find.byType(HisobchiBottomHorizonArc), findsOneWidget);

    await tester.drag(find.byType(Hisobchi3DEmblem), const Offset(32, -20));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Hisobchi3DEmblem));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'HisobchiSplash advances dynamic boot stages cleanly without leaking timers',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: const HisobchiSplash(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Ilova tayyorlanmoqda...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kassa va sinxronizatsiya ulanmoqda...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hisobchi tayyor!'), findsOneWidget);
  });

  testWidgets(
      'mainTabScrollBottomPadding clears floating bottom nav, 3-button bar, and FAB',
      (WidgetTester tester) async {
    late double padWithFab;
    late double padNoFab;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(bottom: 48),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              padWithFab = mainTabScrollBottomPadding(context, hasFab: true);
              padNoFab = mainTabScrollBottomPadding(context, hasFab: false);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(padWithFab, greaterThan(padNoFab));
    expect(padNoFab, greaterThanOrEqualTo(160.0));
    expect(padWithFab, greaterThanOrEqualTo(228.0));
  });

  test('AppPinHasher computes FIPS SHA-256, salted hashes, and enforces HTTPS normalization', () {
    // Known FIPS 180-4 SHA-256("abc") vector
    final digest = AppPinHasher.sha256Bytes(utf8.encode('abc'));
    final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(hex, equals('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'));

    final hashed1 = AppPinHasher.hashPin('2580');
    final hashed2 = AppPinHasher.hashPin('2580');
    expect(AppPinHasher.isHashed(hashed1), isTrue);
    expect(hashed1, isNot(equals(hashed2))); // random salt
    expect(AppPinHasher.verifyPin('2580', hashed1), isTrue);
    expect(AppPinHasher.verifyPin('9999', hashed1), isFalse);
    expect(AppPinHasher.verifyPin('2580', '2580'), isTrue); // legacy compatibility

    expect(
      HisobchiApiClient.normalizeBaseUrl('http://hisobchi.okaposai.uz/'),
      equals('https://hisobchi.okaposai.uz'),
    );
    expect(
      HisobchiApiClient.normalizeBaseUrl('http://127.0.0.1:8088'),
      equals('http://127.0.0.1:8088'),
    );
  });

  testWidgets('PinLockScreen locks keypad for 30s after 5 wrong PIN attempts',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final hashed = AppPinHasher.hashPin('1357');
    var unlocked = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: PinLockScreen(
          mode: PinScreenMode.unlock,
          expectedPin: hashed,
          onCompleted: (_, __) async => unlocked = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> enterPin(String digits) async {
      for (final ch in digits.split('')) {
        await tester.tap(find.text(ch).first);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 120));
    }

    for (var i = 0; i < 5; i++) {
      await enterPin('0000');
    }
    expect(unlocked, isFalse);
    expect(find.textContaining('xato urinish'), findsOneWidget);

    // Keypad is now locked out: entering correct PIN should NOT unlock during cooldown
    await enterPin('1357');
    expect(unlocked, isFalse);
  });
}
