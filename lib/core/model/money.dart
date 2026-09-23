/// An amount of money, held as minor units in an integer.
///
/// **Never use `double` for money.** `0.1 + 0.2 != 0.3` in binary floating
/// point, and a merchant's daily total is a sum of hundreds of such values. A
/// cent that drifts is a dispute we cannot win.
///
/// The backend sends and accepts amounts as decimal *strings* with at most two
/// places (`Decimal = Field(gt=0, max_digits=18, decimal_places=2)`), so this
/// type parses and formats that wire form exactly.
///
/// ## Why [decimals] varies by currency
///
/// XOF (the West African CFA franc) has **no minor unit** — there is no such
/// thing as half a franc, and prices are whole numbers. Rendering `1500` as
/// `1 500,00 F` looks broken to an Ivorian merchant. GHS, NGN and KES do use
/// two decimal places. So the currency decides, not a global constant.
class Money implements Comparable<Money> {
  const Money._(this.minorUnits, this.currency, this.decimals);

  /// Builds an amount from whole major units, e.g. 1500 XOF.
  factory Money.fromMajor(int major, String currency) {
    final code = _normalizeCurrency(currency);
    final decimals = decimalsFor(code);
    return Money._(major * _pow10(decimals), code, decimals);
  }

  /// Rebuilds an amount from stored minor units, e.g. 1550 pesewas = 15.50 GHS.
  ///
  /// This is the inverse of [minorUnits] and the form the local database keeps,
  /// so a round trip through SQLite is exact.
  factory Money.fromMinor(int minorUnits, String currency) {
    final code = _normalizeCurrency(currency);
    return Money._(minorUnits, code, decimalsFor(code));
  }

  /// Parses the backend's decimal-string form, e.g. `"1500.00"`.
  ///
  /// Throws [FormatException] on anything else: a silently-zeroed amount is
  /// far worse than a loud failure.
  factory Money.parse(String value, String currency) {
    final code = _normalizeCurrency(currency);
    final decimals = decimalsFor(code);
    final text = value.trim();
    if (text.isEmpty) {
      throw const FormatException('Empty amount');
    }

    final negative = text.startsWith('-');
    final unsigned = negative ? text.substring(1) : text;

    final parts = unsigned.split('.');
    if (parts.length > 2) {
      throw FormatException('Not a decimal amount: $value');
    }
    final wholePart = parts[0].isEmpty ? '0' : parts[0];
    final fractionPart = parts.length == 2 ? parts[1] : '';

    if (!_digitsOnly(wholePart) ||
        (fractionPart.isNotEmpty && !_digitsOnly(fractionPart))) {
      throw FormatException('Not a decimal amount: $value');
    }

    final whole = int.parse(wholePart);

    // Scale the fraction to this currency's precision. A value carrying more
    // precision than the currency supports is a bug upstream, not something to
    // round away quietly.
    var fraction = 0;
    if (fractionPart.isNotEmpty) {
      final trimmed = _trimTrailingZeros(fractionPart);
      if (trimmed.length > decimals) {
        throw FormatException(
          '$code supports $decimals decimal place(s), got: $value',
        );
      }
      final padded = trimmed.padRight(decimals, '0');
      fraction = padded.isEmpty ? 0 : int.parse(padded);
    }

    final magnitude = whole * _pow10(decimals) + fraction;
    return Money._(negative ? -magnitude : magnitude, code, decimals);
  }

  /// The amount in the currency's smallest indivisible unit: francs for XOF,
  /// pesewas for GHS, kobo for NGN, cents for KES.
  final int minorUnits;

  /// ISO 4217 code, uppercase.
  final String currency;

  /// How many decimal places this currency uses on the wire.
  final int decimals;

  /// Currencies the backend's `/api/config/countries` declares.
  /// XOF is zero-decimal; the rest are two.
  static int decimalsFor(String currency) {
    switch (_normalizeCurrency(currency)) {
      case 'XOF':
      case 'XAF':
        return 0;
      default:
        return 2;
    }
  }

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;

  /// Whole-unit part, e.g. 1500 for 1500.00 XOF or 15 for 15.50 GHS.
  int get whole => minorUnits ~/ _pow10(decimals);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money._(minorUnits + other.minorUnits, currency, decimals);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money._(minorUnits - other.minorUnits, currency, decimals);
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Cannot combine $currency with ${other.currency}; '
        'convert through a rate explicitly',
      );
    }
  }

  /// The exact wire form the backend expects: a plain decimal string with this
  /// currency's number of places, no grouping separators, no symbol.
  String toWireString() {
    final negative = minorUnits < 0;
    final magnitude = minorUnits.abs();
    final sign = negative ? '-' : '';
    if (decimals == 0) return '$sign$magnitude';
    final scale = _pow10(decimals);
    final whole = magnitude ~/ scale;
    final fraction = (magnitude % scale).toString().padLeft(decimals, '0');
    return '$sign$whole.$fraction';
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '${toWireString()} $currency';

  static String _normalizeCurrency(String currency) {
    final code = currency.trim().toUpperCase();
    if (code.length < 3) {
      throw FormatException('Not a currency code: $currency');
    }
    return code;
  }

  static bool _digitsOnly(String value) {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  static String _trimTrailingZeros(String value) {
    var end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    return value.substring(0, end);
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
