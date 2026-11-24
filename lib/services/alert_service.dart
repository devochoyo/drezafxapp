import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/alarm_sound.dart';
import '../models/alert_category.dart';
import '../models/alert_history.dart';
import '../models/currency_pair.dart';
import '../models/forex_alert.dart';
import 'storage_service.dart';

/// Thrown when user input for an alert is invalid.
class AlertValidationException implements Exception {
  const AlertValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Public API for alerts and history (create / read / update / delete).
///
/// After every change [onAlertsChanged] is invoked; `AppServices` uses it to
/// tell the background monitoring isolate to reload.
class AlertService {
  AlertService(
    this._storage, {
    this.onAlertsChanged,
    DateTime Function()? clock,
    String Function()? idGenerator,
  })  : _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? (() => const Uuid().v4());

  final StorageService _storage;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Called after the UI isolate changes alerts.
  void Function()? onAlertsChanged;

  final _changes = StreamController<void>.broadcast();

  /// Emits the current list now and again after every change.
  Stream<List<ForexAlert>> watchAlerts() async* {
    yield await getAlerts();
    yield* _changes.stream.asyncMap((_) => getAlerts());
  }

  /// Call when alerts were changed elsewhere (e.g. the background isolate
  /// marked one as triggered) so [watchAlerts] listeners refresh.
  void notifyExternalChange() => _changes.add(null);

  Future<List<ForexAlert>> getAlerts({AlertStatus? status}) =>
      _storage.getAlerts(status: status);

  Future<ForexAlert?> getAlert(String id) => _storage.getAlert(id);

  /// Creates an active alert. [sound] defaults to the category's sound.
  /// Throws [AlertValidationException] for an invalid price.
  Future<ForexAlert> createAlert({
    required CurrencyPair pair,
    required double targetPrice,
    required AlertCategory category,
    AlarmSound? sound,
  }) async {
    _validatePrice(targetPrice);
    final now = _clock();
    final alert = ForexAlert(
      id: _newId(),
      pair: pair,
      targetPrice: targetPrice,
      category: category,
      sound: sound ?? category.defaultSound,
      createdAt: now,
      updatedAt: now,
    );
    await _storage.saveAlert(alert);
    _changed();
    return alert;
  }

  /// Edits an alert. Editing re-arms it: the crossing reference and any
  /// trigger data are cleared and it becomes active again.
  Future<ForexAlert> updateAlert(
    String id, {
    CurrencyPair? pair,
    double? targetPrice,
    AlertCategory? category,
    AlarmSound? sound,
  }) async {
    final existing = await _storage.getAlert(id);
    if (existing == null) {
      throw AlertValidationException('Alert $id no longer exists.');
    }
    if (targetPrice != null) _validatePrice(targetPrice);
    final updated = existing
        .copyWith(
          pair: pair,
          targetPrice: targetPrice,
          category: category,
          sound: sound,
          status: AlertStatus.active,
          updatedAt: _clock(),
          clearPreviousPrice: true,
          clearTrigger: true,
        );
    await _storage.saveAlert(updated);
    _changed();
    return updated;
  }

  /// Makes a triggered alert active again with the same settings.
  Future<ForexAlert> rearmAlert(String id) => updateAlert(id);

  Future<void> deleteAlert(String id) async {
    await _storage.deleteAlert(id);
    _changed();
  }

  /// Alert history, newest first.
  Future<List<AlertHistory>> getHistory() => _storage.getHistory();

  Future<void> clearHistory() => _storage.clearHistory();

  Future<void> dispose() => _changes.close();

  void _changed() {
    _changes.add(null);
    onAlertsChanged?.call();
  }

  void _validatePrice(double price) {
    if (!price.isFinite || price <= 0) {
      throw const AlertValidationException(
          'Enter a valid target price greater than zero.');
    }
  }
}
