import '../core/model/money.dart';

/// Formats an amount the way a merchant in the region reads it.
///
/// French convention: a space groups thousands and a comma marks the decimal,
/// so 1500 XOF is `1 500 F` — not `1,500.00 XOF`.
///
/// XOF is rendered with no decimal part at all, because the franc has no minor
/// unit. Showing `1 500,00 F` to an Ivorian merchant looks like a bug.
///
/// Hand-rolled rather than `NumberFormat`: this needs a non-breaking space as
/// the group separator so a price never wraps mid-number, and per-currency
/// symbol placement that `intl`'s locale data does not give us for XOF.
String formatMoney(Money amount, {bool withSymbol = true}) {
  final negative = amount.isNegative;
  final magnitude = amount.minorUnits.abs();

  final scale = _pow10(amount.decimals);
  final whole = magnitude ~/ scale;
  final fraction = magnitude % scale;

  final buffer = StringBuffer();
  if (negative) buffer.write('-');
  buffer.write(_group(whole));
  if (amount.decimals > 0) {
    buffer.write(',');
    buffer.write(fraction.toString().padLeft(amount.decimals, '0'));
  }
  if (withSymbol) {
    buffer.write(' ');
    buffer.write(symbolFor(amount.currency));
  }
  return buffer.toString();
}

/// The short symbol merchants actually use, not the ISO code.
String symbolFor(String currency) => switch (currency.toUpperCase()) {
      // "F CFA" in full, but a single F is what is written on a price tag.
      'XOF' => 'F',
      'XAF' => 'F',
      'GHS' => 'GH₵',
      'NGN' => '₦',
      'KES' => 'KSh',
      _ => currency.toUpperCase(),
    };

/// Groups thousands with a non-breaking space, per French convention.
String _group(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;
  final buffer = StringBuffer();
  final firstGroup = digits.length % 3;
  var index = 0;
  if (firstGroup > 0) {
    buffer.write(digits.substring(0, firstGroup));
    index = firstGroup;
  }
  while (index < digits.length) {
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(digits.substring(index, index + 3));
    index += 3;
  }
  return buffer.toString();
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
