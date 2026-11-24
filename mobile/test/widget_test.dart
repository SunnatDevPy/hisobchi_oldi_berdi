import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisobchi_app/api_client.dart';
import 'package:hisobchi_app/main.dart';
import 'package:hisobchi_app/offline_sync.dart';
import 'package:hisobchi_app/theme.dart';
import 'package:hisobchi_app/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
}
