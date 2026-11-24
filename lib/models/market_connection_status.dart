import 'model_utils.dart';

enum MarketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Connection status reported by a market-data provider.
class MarketConnectionStatus {
  const MarketConnectionStatus(this.state, {this.message, DateTime? at})
      : _at = at;

  static const MarketConnectionStatus disconnected =
      MarketConnectionStatus(MarketConnectionState.disconnected);

  factory MarketConnectionStatus.fromJson(Map<String, dynamic> json) =>
      MarketConnectionStatus(
        enumFromName(MarketConnectionState.values, json['state'] as String?,
            MarketConnectionState.disconnected),
        message: json['message'] as String?,
        at: dateFromJsonOrNull(json['at']),
      );

  final MarketConnectionState state;

  /// Human-readable detail, e.g. the error text.
  final String? message;
  final DateTime? _at;

  /// When the status was reported (null for the const defaults).
  DateTime? get at => _at;

  bool get isConnected => state == MarketConnectionState.connected;

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'message': message,
        'at': _at == null ? null : dateToJson(_at!),
      };

  @override
  String toString() => 'MarketConnectionStatus(${state.name}, $message)';
}
