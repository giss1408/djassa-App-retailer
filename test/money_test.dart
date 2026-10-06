import 'package:hossouko_merchant/core/model/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('parses the backend decimal-string form for a 2-decimal currency', () {
      final m = Money.parse('15.50', 'GHS');
      expect(m.minorUnits, 1550);
      expect(m.decimals, 2);
      expect(m.toWireString(), '15.50');
    });

    test('treats XOF as zero-decimal', () {
      final m = Money.parse('1500', 'XOF');
      expect(m.minorUnits, 1500);
      expect(m.decimals, 0);
      // Must not render as 1500.00: XOF has no minor unit.
      expect(m.toWireString(), '1500');
    });

    test('accepts the .00 the backend sends for XOF and keeps the value', () {
      // Decimal(18,2) serialises 1500 as "1500.00" even for XOF.
      expect(Money.parse('1500.00', 'XOF').minorUnits, 1500);
      expect(Money.parse('1500.00', 'XOF').toWireString(), '1500');
    });

    test('rejects precision the currency cannot represent', () {
      expect(() => Money.parse('15.50', 'XOF'), throwsFormatException);
      expect(() => Money.parse('15.555', 'GHS'), throwsFormatException);
    });

    test('rejects junk rather than silently yielding zero', () {
      expect(() => Money.parse('', 'XOF'), throwsFormatException);
      expect(() => Money.parse('abc', 'XOF'), throwsFormatException);
      expect(() => Money.parse('1.2.3', 'GHS'), throwsFormatException);
      expect(() => Money.parse('1 500', 'XOF'), throwsFormatException);
    });

    test('round-trips every currency the backend supports', () {
      for (final (value, currency) in const [
        ('1500', 'XOF'),
        ('15.50', 'GHS'),
        ('2000.99', 'NGN'),
        ('350.05', 'KES'),
      ]) {
        expect(Money.parse(value, currency).toWireString(), value);
      }
    });

    test('is exact where double would drift', () {
      // 0.1 + 0.2 == 0.30000000000000004 as a double.
      final sum = Money.parse('0.10', 'GHS') + Money.parse('0.20', 'GHS');
      expect(sum.toWireString(), '0.30');

      // A day of small sales must total exactly.
      var total = Money.fromMajor(0, 'XOF');
      for (var i = 0; i < 1000; i++) {
        total = total + Money.parse('125', 'XOF');
      }
      expect(total.toWireString(), '125000');
    });
  });

  group('Money arithmetic', () {
    test('refuses to mix currencies', () {
      expect(
        () => Money.parse('100', 'XOF') + Money.parse('1.00', 'GHS'),
        throwsArgumentError,
      );
    });

    test('normalises the currency code', () {
      expect(Money.parse('100', 'xof').currency, 'XOF');
    });

    test('equality is by value and currency', () {
      expect(Money.parse('100', 'XOF'), Money.fromMajor(100, 'XOF'));
      expect(Money.parse('100', 'XOF'), isNot(Money.parse('100', 'KES')));
    });
  });
}
