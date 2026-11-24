import '../models/currency_pair.dart';
import '../models/forex_alert.dart';
import '../models/market_price.dart';

/// Result of evaluating one price against one alert.
class EvaluationResult {
  const EvaluationResult({
    required this.alert,
    required this.triggered,
    this.direction,
  });

  /// The alert after evaluation (new [ForexAlert.previousPrice]; trigger
  /// fields and status set when [triggered]).
  final ForexAlert alert;
  final bool triggered;
  final CrossingDirection? direction;
}

/// Pure, side-effect-free exact-price crossing detection.
///
/// The direction is never configured: it is derived from two consecutive
/// observations. Prices are compared as integer ticks
/// ([CurrencyPair.toTicks]), never with floating-point equality.
///
/// Rules (side = sign of price minus target, in ticks):
/// * upward cross:   previous below target AND current at or above target
/// * downward cross: previous above target AND current at or below target
/// * no previous price -> the quote only becomes the reference; it can never
///   trigger, even if it is beyond or exactly on the target
/// * a jump over the target triggers; the actual price is recorded
/// * a triggered alert is never evaluated again (no duplicates) until
///   re-armed
class AlertEvaluationService {
  const AlertEvaluationService();

  /// Evaluates [price] against [alert].
  EvaluationResult evaluate(
    ForexAlert alert,
    MarketPrice price, {
    DateTime? now,
  }) {
    if (!alert.isActive || price.pair != alert.pair || !price.isValid) {
      return EvaluationResult(alert: alert, triggered: false);
    }

    final direction = detectCrossing(
      pair: alert.pair,
      previous: alert.previousPrice,
      target: alert.targetPrice,
      current: price.price,
    );

    if (direction == null) {
      return EvaluationResult(
        alert: alert.copyWith(previousPrice: price.price),
        triggered: false,
      );
    }

    final at = now ?? DateTime.now();
    return EvaluationResult(
      alert: alert.copyWith(
        status: AlertStatus.triggered,
        previousPrice: price.price,
        triggeredAt: at,
        triggerPrice: price.price,
        triggerDirection: direction,
        updatedAt: at,
      ),
      triggered: true,
      direction: direction,
    );
  }

  /// Returns the crossing direction, or null when there is no crossing.
  static CrossingDirection? detectCrossing({
    required CurrencyPair pair,
    required double? previous,
    required double target,
    required double current,
  }) {
    if (previous == null) return null;
    final targetTicks = pair.toTicks(target);
    final prevSide = pair.toTicks(previous).compareTo(targetTicks);
    final currSide = pair.toTicks(current).compareTo(targetTicks);
    if (prevSide < 0 && currSide >= 0) return CrossingDirection.upward;
    if (prevSide > 0 && currSide <= 0) return CrossingDirection.downward;
    return null;
  }

  /// Forgets the crossing reference (after a reconnect or an edit). The next
  /// quote becomes the new reference and cannot trigger.
  ForexAlert resetReference(ForexAlert alert) =>
      alert.copyWith(clearPreviousPrice: true);
}
