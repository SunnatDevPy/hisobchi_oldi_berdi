import 'package:flutter_test/flutter_test.dart';
import 'package:hisobchi_app/api_client.dart';
import 'package:hisobchi_app/main.dart';
import 'package:hisobchi_app/theme.dart';

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
}
