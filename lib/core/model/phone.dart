/// Customer phone numbers, as a merchant types them at the counter.
///
/// Mirrors the backend's rule (`hossouko-BE/backend-api/app/core/phone.py`):
/// loyalty points are keyed on the number, so "07 12 34 56 78", "0712345678"
/// and "+225 07 12 34 56 78" must all become the same `+2250712345678`, and
/// anything that is not an Ivorian number is refused on the phone — before the
/// sale is saved — rather than by the server hours later, when the customer
/// has long left.
library;

final _separators = RegExp(r'[\s.\-()/]');

/// The E.164 form of [raw], or null when it is not a valid Ivorian number.
///
/// Côte d'Ivoire has used ten-digit national numbers since 2021.
String? normalizeIvorianPhone(String raw) {
  var digits = raw.replaceAll(_separators, '');
  if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
  if (RegExp(r'^\+225\d{10}$').hasMatch(digits)) return digits;
  if (RegExp(r'^0\d{9}$').hasMatch(digits)) return '+225$digits';
  return null;
}
