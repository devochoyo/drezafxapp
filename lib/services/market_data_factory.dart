import 'deriv_market_data_service.dart';
import 'market_data_service.dart';
import 'storage_service.dart';

/// The single place where the production market-data provider is created.
///
/// Provider: Deriv public WebSocket tick stream (see
/// deriv_market_data_service.dart). It needs no account, token or app ID, so
/// there is nothing to set up. There is no fallback to any other data source.
MarketDataService createMarketDataService(StorageService storage) =>
    DerivMarketDataService();
