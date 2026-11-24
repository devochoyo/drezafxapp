import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/screens.dart';
import 'services/alarm_adapter.dart';
import 'services/alerts_adapter.dart';
import 'services/app_services.dart';
import 'services/history_adapter.dart';
import 'services/market_price_adapter.dart';
import 'services/notification_service.dart';
import 'services/settings_adapter.dart';
import 'services/sound_adapter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Services (storage, notifications, audio, monitoring) must be ready
  // before any screen uses them.
  await AppServices.instance.initialize();
  runApp(const DrezaFxApp());
}

class DrezaFxApp extends StatefulWidget {
  const DrezaFxApp({super.key});

  @override
  State<DrezaFxApp> createState() => _DrezaFxAppState();
}

class _DrezaFxAppState extends State<DrezaFxApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  // Adapters are created once and disposed in dispose().
  late final AlertsAdapter _alerts;
  late final MarketPriceAdapter _market;
  late final SoundAdapter _sounds;
  late final AlarmAdapter _alarms;
  late final HistoryAdapter _history;
  late final SettingsAdapter _settings;

  StreamSubscription<String>? _tapSub;

  @override
  void initState() {
    super.initState();
    final services = AppServices.instance;
    _alerts = AlertsAdapter(services.alerts);
    _market = MarketPriceAdapter(services.monitoring);
    _sounds = SoundAdapter(services.alarm, services.storage);
    _alarms = AlarmAdapter(
      storage: services.storage,
      monitoring: services.monitoring,
      stopAlarmAction: services.stopAlarm,
    );
    _history = HistoryAdapter(services.alerts);
    _settings = SettingsAdapter(
      storage: services.storage,
      notifications: services.notifications,
      monitoring: services.monitoring,
    );

    WidgetsBinding.instance.addObserver(this);
    _tapSub = services.notifications.tapStream.listen(_onNotificationTap);
    _startUp();
  }

  /// Asks for notification permission (Android 13+), starts background
  /// monitoring if enabled in settings, and handles a notification that
  /// launched the app.
  Future<void> _startUp() async {
    final services = AppServices.instance;
    try {
      final settings = await services.storage.getSettings();
      if (settings.notificationsEnabled) {
        await services.notifications.requestPermission();
      }
      if (settings.monitoringEnabled) {
        await services.startMonitoring();
      }
      final launchPayload = await services.notifications.getLaunchPayload();
      _onNotificationTap(launchPayload);
    } catch (_) {
      // Start-up problems must not stop the UI. Monitoring status is shown
      // on the Dashboard and in Settings.
    }
  }

  /// A tap on the alarm notification: re-read the saved alarm state. If an
  /// alarm is ringing, AlarmRouteCoordinator opens the Active Alarm screen
  /// (and never opens a second copy).
  void _onNotificationTap(String? payload) {
    if (NotificationPayload.alertIdFrom(payload) != null) {
      _alarms.refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The alarm may have started while the app was in the background.
    if (state == AppLifecycleState.resumed) _alarms.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tapSub?.cancel();
    _alarms.dispose();
    _market.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Both service providers must sit above MaterialApp.
    return ScreenServices(
      alerts: _alerts,
      market: _market,
      sounds: _sounds,
      child: Stage2Services(
        alarms: _alarms,
        history: _history,
        settings: _settings,
        child: MaterialApp(
          title: 'DrezaFx',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: buildDrezaTheme(),
          builder: (context, child) => AlarmRouteCoordinator(
            navigatorKey: _navigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const DrezaFxHome(),
        ),
      ),
    );
  }
}
