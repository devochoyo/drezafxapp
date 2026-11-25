/// Pair codes are upper-case without a slash ("EURUSD"). Display uses a slash.
///
/// NOTE: this list is a UI selection list only. It does not imply a working
/// live feed for any pair; the market-data provider decides what is supported.
const List<String> kSupportedPairs = [
  'EURUSD', 'GBPUSD', 'USDJPY', 'USDCHF', 'USDCAD', 'AUDUSD', 'NZDUSD',
  'EURGBP', 'EURJPY', 'GBPJPY', 'AUDJPY', 'AUDCAD', 'AUDCHF', 'AUDNZD',
  'CADCHF', 'CADJPY', 'CHFJPY', 'EURAUD', 'EURCAD', 'EURCHF', 'EURNZD',
  'GBPAUD', 'GBPCAD', 'GBPCHF', 'GBPNZD', 'NZDCAD', 'NZDCHF', 'NZDJPY',
  'USDMXN', 'USDNOK', 'USDSEK', 'USDPLN', 'USDZAR', 'USDSGD', 'USDTRY',
  'EURNOK', 'EURSEK', 'EURPLN', 'GBPNOK', 'GBPPLN', 'XAUUSD', 'XAGUSD',
];

String pairDisplay(String code) =>
    code.length == 6 ? '${code.substring(0, 3)}/${code.substring(3)}' : code;

String quoteCurrency(String code) =>
    code.length >= 6 ? code.substring(3, 6) : '';

/// Natural decimals: JPY pairs 3, XAU 2, everything else 5 (typography.md).
int pricePrecision(String code) {
  final c = code.toUpperCase();
  if (c.startsWith('XAU')) return 2;
  if (c.startsWith('XAG')) return 3;
  if (c.endsWith('JPY')) return 3;
  return 5;
}

/// Display format with thousands separators, e.g. 2,035.50.
String formatPrice(double v, String pairCode) {
  final s = v.toStringAsFixed(pricePrecision(pairCode));
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final fromEnd = intPart.length - i;
    buf.write(intPart[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  return parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
}

/// Plain editable format (no separators), used to prefill the Edit form.
String editablePrice(double v, String pairCode) =>
    v.toStringAsFixed(pricePrecision(pairCode));

String _normalise(String s) => s.trim().replaceAll(',', '.');

double? parseTargetPrice(String input) {
  final s = _normalise(input);
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v.isNaN || v.isInfinite || v <= 0) return null;
  return v;
}

/// Returns an error message, or null when valid.
String? validateTargetPrice(String input, String pairCode) {
  const generic = 'Enter a valid target price';
  final v = parseTargetPrice(input);
  if (v == null) return generic;
  final s = _normalise(input);
  final dot = s.indexOf('.');
  if (dot >= 0) {
    final decimals = s.length - dot - 1;
    final max = pricePrecision(pairCode);
    if (decimals > max) {
      return 'Use at most $max decimal places for ${pairDisplay(pairCode)}';
    }
  }
  return null;
}
