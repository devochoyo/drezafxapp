/// OANDA v20 API credentials entered by the owner in Settings.
/// Stored only in the app's private storage, never in source code.
class MarketCredentials {
  const MarketCredentials({
    required this.accountId,
    required this.token,
    this.live = false,
  });

  factory MarketCredentials.fromJson(Map<String, dynamic> json) =>
      MarketCredentials(
        accountId: (json['accountId'] as String? ?? '').trim(),
        token: (json['token'] as String? ?? '').trim(),
        live: json['live'] as bool? ?? false,
      );

  /// OANDA account ID, e.g. "101-001-1234567-001".
  final String accountId;

  /// OANDA personal access token.
  final String token;

  /// false = fxTrade Practice (free demo account), true = fxTrade live.
  final bool live;

  bool get isComplete => accountId.isNotEmpty && token.isNotEmpty;

  MarketCredentials copyWith({String? accountId, String? token, bool? live}) =>
      MarketCredentials(
        accountId: accountId ?? this.accountId,
        token: token ?? this.token,
        live: live ?? this.live,
      );

  Map<String, dynamic> toJson() =>
      {'accountId': accountId, 'token': token, 'live': live};
}
