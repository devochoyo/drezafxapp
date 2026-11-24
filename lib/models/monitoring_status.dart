import 'market_connection_status.dart';
import 'model_utils.dart';

/// State of the background monitoring service itself.
enum MonitoringServiceState {
  /// Not running (never started, stopped by the user, or killed by Android).
  stopped,

  /// Service process is starting.
  starting,

  /// Service is running and the engine is evaluating alerts.
  running,
}

/// Everything the UI needs to show "is monitoring working?".
class MonitoringStatus {
  const MonitoringStatus({
    this.serviceState = MonitoringServiceState.stopped,
    this.connection = MarketConnectionStatus.disconnected,
    this.activeAlertCount = 0,
    this.watchedPairs = const [],
    this.lastPriceAt,
    this.lastError,
  });

  static const MonitoringStatus stopped = MonitoringStatus();

  factory MonitoringStatus.fromJson(Map<String, dynamic> json) =>
      MonitoringStatus(
        serviceState: enumFromName(MonitoringServiceState.values,
            json['serviceState'] as String?, MonitoringServiceState.stopped),
        connection: json['connection'] == null
            ? MarketConnectionStatus.disconnected
            : MarketConnectionStatus.fromJson(
                Map<String, dynamic>.from(json['connection'] as Map)),
        activeAlertCount: json['activeAlertCount'] as int? ?? 0,
        watchedPairs:
            ((json['watchedPairs'] as List?) ?? const []).cast<String>(),
        lastPriceAt: dateFromJsonOrNull(json['lastPriceAt']),
        lastError: json['lastError'] as String?,
      );

  final MonitoringServiceState serviceState;
  final MarketConnectionStatus connection;
  final int activeAlertCount;

  /// Symbols currently subscribed, e.g. ["EURUSD", "GBPUSD"].
  final List<String> watchedPairs;

  /// When the last valid price arrived.
  final DateTime? lastPriceAt;
  final String? lastError;

  bool get isServiceRunning => serviceState == MonitoringServiceState.running;

  /// True only when the service runs AND live prices are flowing.
  bool get isFullyOperational => isServiceRunning && connection.isConnected;

  MonitoringStatus copyWith({
    MonitoringServiceState? serviceState,
    MarketConnectionStatus? connection,
    int? activeAlertCount,
    List<String>? watchedPairs,
    DateTime? lastPriceAt,
    String? lastError,
    bool clearLastError = false,
  }) =>
      MonitoringStatus(
        serviceState: serviceState ?? this.serviceState,
        connection: connection ?? this.connection,
        activeAlertCount: activeAlertCount ?? this.activeAlertCount,
        watchedPairs: watchedPairs ?? this.watchedPairs,
        lastPriceAt: lastPriceAt ?? this.lastPriceAt,
        lastError: clearLastError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => {
        'serviceState': serviceState.name,
        'connection': connection.toJson(),
        'activeAlertCount': activeAlertCount,
        'watchedPairs': watchedPairs,
        'lastPriceAt': lastPriceAt == null ? null : dateToJson(lastPriceAt!),
        'lastError': lastError,
      };
}
