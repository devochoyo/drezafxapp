import 'dart:math' as math;

/// A Forex instrument such as EUR/USD.
///
/// Identity is the 6-letter [symbol] (as used by MetaTrader 5, e.g. "EURUSD").
/// [pricePrecision] is the number of decimals used to *compare* prices, which
/// avoids floating-point equality problems (see [toTicks]).
class CurrencyPair {
  const CurrencyPair._(this.base, this.quote, this.pricePrecision);

  /// Base currency code, e.g. "EUR".
  final String base;

  /// Quote currency code, e.g. "USD".
  final String quote;

  /// Decimal places used for comparison and display.
  ///
  /// 5 for most pairs, 3 for JPY-quoted pairs, 2 for XAU (gold).
  /// This is the finest resolution DrezaFx distinguishes. A broker quoting
  /// fewer decimals is still handled correctly.
  final int pricePrecision;

  /// Parses "EURUSD", "eur/usd", "EUR-USD" ... Throws [FormatException] when
  /// the input is not exactly two 3-letter codes.
  factory CurrencyPair.fromSymbol(String raw) {
    final symbol = raw.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
    if (symbol.length != 6) {
      throw FormatException('Not a 6-letter currency pair: "$raw"');
    }
    final base = symbol.substring(0, 3);
    final quote = symbol.substring(3);
    return CurrencyPair._(base, quote, _precisionFor(base, quote));
  }

  /// Like [CurrencyPair.fromSymbol] but returns null instead of throwing.
  static CurrencyPair? tryParse(String raw) {
    try {
      return CurrencyPair.fromSymbol(raw);
    } on FormatException {
      return null;
    }
  }

  factory CurrencyPair.fromJson(Object? json) {
    if (json is String) return CurrencyPair.fromSymbol(json);
    throw FormatException('Invalid currency pair value: $json');
  }

  static int _precisionFor(String base, String quote) {
    if (base == 'XAU') return 2;
    if (base == 'XAG') return 3;
    if (quote == 'JPY') return 3;
    return 5;
  }

  /// Instruments offered by default. Batch 2 may show these in a picker; any
  /// other 6-letter symbol can still be created with [CurrencyPair.fromSymbol].
  static const List<CurrencyPair> supported = [
    CurrencyPair._('EUR', 'USD', 5),
    CurrencyPair._('GBP', 'USD', 5),
    CurrencyPair._('USD', 'JPY', 3),
    CurrencyPair._('USD', 'CHF', 5),
    CurrencyPair._('USD', 'CAD', 5),
    CurrencyPair._('AUD', 'USD', 5),
    CurrencyPair._('NZD', 'USD', 5),
    CurrencyPair._('EUR', 'GBP', 5),
    CurrencyPair._('EUR', 'JPY', 3),
    CurrencyPair._('GBP', 'JPY', 3),
    CurrencyPair._('AUD', 'JPY', 3),
    CurrencyPair._('AUD', 'CAD', 5),
    CurrencyPair._('AUD', 'CHF', 5),
    CurrencyPair._('AUD', 'NZD', 5),
    CurrencyPair._('CAD', 'CHF', 5),
    CurrencyPair._('CAD', 'JPY', 3),
    CurrencyPair._('CHF', 'JPY', 3),
    CurrencyPair._('EUR', 'AUD', 5),
    CurrencyPair._('EUR', 'CAD', 5),
    CurrencyPair._('EUR', 'CHF', 5),
    CurrencyPair._('EUR', 'NZD', 5),
    CurrencyPair._('GBP', 'AUD', 5),
    CurrencyPair._('GBP', 'CAD', 5),
    CurrencyPair._('GBP', 'CHF', 5),
    CurrencyPair._('GBP', 'NZD', 5),
    CurrencyPair._('NZD', 'CAD', 5),
    CurrencyPair._('NZD', 'CHF', 5),
    CurrencyPair._('NZD', 'JPY', 3),
    CurrencyPair._('USD', 'MXN', 5),
    CurrencyPair._('USD', 'NOK', 5),
    CurrencyPair._('USD', 'SEK', 5),
    CurrencyPair._('USD', 'PLN', 5),
    CurrencyPair._('USD', 'ZAR', 5),
    CurrencyPair._('USD', 'SGD', 5),
    CurrencyPair._('USD', 'TRY', 5),
    CurrencyPair._('EUR', 'NOK', 5),
    CurrencyPair._('EUR', 'SEK', 5),
    CurrencyPair._('EUR', 'PLN', 5),
    CurrencyPair._('GBP', 'NOK', 5),
    CurrencyPair._('GBP', 'PLN', 5),
    CurrencyPair._('XAU', 'USD', 2),
    CurrencyPair._('XAG', 'USD', 3),
  ];

  /// MetaTrader-style symbol, e.g. "EURUSD".
  String get symbol => '$base$quote';

  /// Human-readable name, e.g. "EUR/USD".
  String get displayName => '$base/$quote';

  /// Size of one price step at [pricePrecision] (e.g. 0.00001).
  double get tickSize => 1 / math.pow(10, pricePrecision);

  /// Converts [price] to an integer number of ticks. Comparing ticks instead
  /// of doubles removes binary floating-point noise
  /// (1.0850000000000002 and 1.0850 are the same tick count).
  int toTicks(double price) =>
      (price * math.pow(10, pricePrecision)).round();

  /// Formats [price] with this pair's precision, e.g. "1.08500".
  String format(double price) => price.toStringAsFixed(pricePrecision);

  String toJson() => symbol;

  @override
  bool operator ==(Object other) =>
      other is CurrencyPair && other.symbol == symbol;

  @override
  int get hashCode => symbol.hashCode;

  @override
  String toString() => displayName;
}
