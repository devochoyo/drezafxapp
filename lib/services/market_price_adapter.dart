import 'dart:async';

import '../models/market_connection_status.dart';
import '../models/market_price.dart';
import '../models/monitoring_status.dart';
import '../screens/contracts/screen_contracts.dart' as ui;
import 'background_monitoring_service.dart';

/// Connects the screens' MarketPriceGateway to the monitoring service.
///
/// Prices come only from the real price stream sent by the monitoring
/// isolate. Nothing is generated here. When the connection is not "connected"
/// the price map is emptied, so the Dashboard shows "—" instead of an old
/// price. Without OANDA credentials the status is "disconnected" with the
/// reason, and there are no prices.
class MarketPriceAdapter implements ui.MarketPriceGateway {
  MarketPriceAdapter(this._monitoring) {
    _status = _monitoring.currentStatus;
    _statusSub = _monitoring.statusStream.listen((status) {
      _status = status;
      if (!_isConnected) _prices.clear();
      _publish();
    });
    _priceSub = _monitoring.priceStream.listen(_onPrice);
  }

  final BackgroundMonitoringService _monitoring;
  late MonitoringStatus _status;
  final Map<String, double> _prices = {};
  final _controller = StreamController<ui.MarketSnapshot>.broadcast();
  StreamSubscription<MonitoringStatus>? _statusSub;
  StreamSubscription<MarketPrice>? _priceSub;

  bool get _isConnected =>
      _status.isServiceRunning && _status.connection.isConnected;

  void _onPrice(MarketPrice price) {
    if (!price.isValid || !_isConnected) return;
    _prices[price.pair.symbol] = price.price;
    _publish();
  }

  ui.MarketSnapshot _snapshot() {
    final ui.MarketConnectionStatus state;
    if (!_status.isServiceRunning) {
      state = _status.serviceState == MonitoringServiceState.starting
          ? ui.MarketConnectionStatus.connecting
          : ui.MarketConnectionStatus.disconnected;
    } else {
      switch (_status.connection.state) {
        case MarketConnectionState.connected:
          state = ui.MarketConnectionStatus.connected;
          break;
        case MarketConnectionState.connecting:
        case MarketConnectionState.reconnecting:
          state = ui.MarketConnectionStatus.connecting;
          break;
        case MarketConnectionState.disconnected:
          state = ui.MarketConnectionStatus.disconnected;
          break;
        case MarketConnectionState.error:
          state = ui.MarketConnectionStatus.error;
          break;
      }
    }
    return ui.MarketSnapshot(
      status: state,
      prices: Map.unmodifiable(_prices),
      errorMessage: state == ui.MarketConnectionStatus.error ||
              state == ui.MarketConnectionStatus.disconnected
          ? (_status.connection.message ?? _status.lastError)
          : null,
    );
  }

  void _publish() {
    if (!_controller.isClosed) _controller.add(_snapshot());
  }

  @override
  Stream<ui.MarketSnapshot> get snapshots async* {
    yield _snapshot();
    yield* _controller.stream;
  }

  /// "Retry" on the Dashboard banner: re-opens the market-data connection
  /// (starting the monitoring service first if needed).
  @override
  void retry() {
    _monitoring.reconnectMarket();
  }

  Future<void> dispose() async {
    await _statusSub?.cancel();
    await _priceSub?.cancel();
    await _controller.close();
  }
}
