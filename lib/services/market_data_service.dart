import '../models/currency_pair.dart';
import '../models/market_connection_status.dart';
import '../models/market_price.dart';

/// Provider-independent source of live Forex prices.
///
/// A real provider (REST polling, WebSocket, ...) implements this interface
/// and is wired in at ONE place: `createMarketDataService()` in
/// `market_data_factory.dart`. No provider, endpoint or credential has been
/// selected yet.
///
/// Contract for implementations:
/// * [priceStream] and [statusStream] are broadcast streams.
/// * Emit a new [MarketPrice] per quote; the engine compares consecutive
///   quotes, so prices must arrive in chronological order per pair.
/// * Handle reconnection internally and report it through [statusStream]
///   (`reconnecting` -> `connected`). The engine resets its crossing
///   references whenever the status returns to `connected`.
/// * [subscribe] may be called before [connect]; subscriptions must survive
///   reconnects.
/// * Never fabricate prices.
abstract class MarketDataService {
  /// Current connection status.
  MarketConnectionStatus get status;

  /// Emits whenever [status] changes.
  Stream<MarketConnectionStatus> get statusStream;

  /// Live price updates for all subscribed pairs.
  Stream<MarketPrice> get priceStream;

  /// Pairs currently subscribed.
  Set<CurrencyPair> get subscribedPairs;

  /// Opens the connection. Throws [MarketDataException] if it cannot start
  /// (for example [MarketDataNotConfiguredException]).
  Future<void> connect();

  /// Closes the connection. Subscriptions are kept for a later [connect].
  Future<void> disconnect();

  /// Starts receiving prices for [pair].
  Future<void> subscribe(CurrencyPair pair);

  /// Stops receiving prices for [pair].
  Future<void> unsubscribe(CurrencyPair pair);

  /// Latest price received for [pair], or null if none yet.
  MarketPrice? getLatestPrice(CurrencyPair pair);

  /// Disconnects and releases all resources. The instance is unusable after.
  Future<void> dispose();
}

/// Problem reported by a market-data provider.
class MarketDataException implements Exception {
  const MarketDataException(this.message);
  final String message;

  /// Retrying cannot help (for example no provider configured).
  bool get isPermanent => false;

  @override
  String toString() => 'MarketDataException: $message';
}

/// Thrown by [UnconfiguredMarketDataService]: no real provider is wired in.
class MarketDataNotConfiguredException extends MarketDataException {
  const MarketDataNotConfiguredException()
      : super('No market-data provider is configured. '
            'Implement MarketDataService and return it from '
            'createMarketDataService().');

  @override
  bool get isPermanent => true;
}
