import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisobchi_app/api_client.dart';
import 'package:hisobchi_app/main.dart';
import 'package:hisobchi_app/theme.dart';
import 'package:hisobchi_app/widgets.dart';

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
}
