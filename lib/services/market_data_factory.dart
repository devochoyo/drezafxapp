import 'market_data_service.dart';
import 'oanda_market_data_service.dart';
import 'storage_service.dart';

/// The single place where the production market-data provider is created.
///
/// Provider: OANDA v20 pricing stream (see oanda_market_data_service.dart).
/// Credentials (account ID + API token) are entered by the owner in
/// Settings > Market data and read from [storage] when connecting. Without
/// credentials the service reports "not set up" - it never produces prices.
/// There is no fallback to any other data source.
MarketDataService createMarketDataService(StorageService storage) =>
    OandaMarketDataService(loadCredentials: storage.getMarketCredentials);
