import 'currency_pair.dart';
import 'model_utils.dart';

/// One price observation for a [CurrencyPair].
class MarketPrice {
  const MarketPrice({
    required this.pair,
    required this.price,
    required this.timestamp,
    this.bid,
    this.ask,
  });

  /// Builds a price from a bid/ask quote.
  ///
  /// [price] is set to the **bid**, because MetaTrader 5 charts and the
  /// price lines the user copies from them are drawn on the bid. If you
  /// change this, change it for every provider consistently.
  factory MarketPrice.fromBidAsk({
    required CurrencyPair pair,
    required double bid,
    required double ask,
    required DateTime timestamp,
  }) =>
      MarketPrice(
        pair: pair,
        price: bid,
        bid: bid,
        ask: ask,
        timestamp: timestamp,
      );

  factory MarketPrice.fromJson(Map<String, dynamic> json) => MarketPrice(
        pair: CurrencyPair.fromJson(json['pair']),
        price: (json['price'] as num).toDouble(),
        bid: (json['bid'] as num?)?.toDouble(),
        ask: (json['ask'] as num?)?.toDouble(),
        timestamp: dateFromJson(json['timestamp']),
      );

  final CurrencyPair pair;

  /// The price used for alert evaluation (see [MarketPrice.fromBidAsk]).
  final double price;

  final double? bid;
  final double? ask;
  final DateTime timestamp;

  /// Decimals for this price (taken from the pair).
  int get precision => pair.pricePrecision;

  /// Price formatted with [precision] decimals.
  String get formattedPrice => pair.format(price);

  /// Ask minus bid, when both are available.
  double? get spread => (bid != null && ask != null) ? ask! - bid! : null;

  /// Midpoint of bid and ask, when both are available.
  double? get mid => (bid != null && ask != null) ? (bid! + ask!) / 2 : null;

  /// False for NaN, infinite or non-positive prices, which must be ignored.
  bool get isValid => price.isFinite && price > 0;

  Map<String, dynamic> toJson() => {
        'pair': pair.toJson(),
        'price': price,
        'bid': bid,
        'ask': ask,
        'timestamp': dateToJson(timestamp),
      };

  @override
  String toString() => 'MarketPrice($pair $formattedPrice @ $timestamp)';
}
