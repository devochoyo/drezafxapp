import 'dart:async';
import 'package:flutter/material.dart';
import '../../chart/screen/chart_screen.dart';
import '../alarm/active_alarm_screen.dart';
import '../contracts/stage2_contracts.dart';
import '../dashboard/dashboard_screen.dart';
import '../history/alert_history_screen.dart';
import '../settings/settings_screen.dart';

/// Central navigation for the combined screen set.
///
/// Structure: Dashboard is the ROOT route. Chart, History and Settings are
/// pushed on top of it (fade transition) and switch between each other with
/// pushReplacement, so the stack never grows beyond Dashboard + one tab.
/// Active Alarm is pushed on top of whatever is showing.
class DzNav {
  DzNav._();

  static Route<T> _fade<T>(Widget page) => PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      );

  /// Back to the Dashboard (root), closing Chart/History/Settings/Alarm.
  static void home(BuildContext context) =>
      Navigator.of(context).popUntil((r) => r.isFirst);

  /// Opens Chart from the Dashboard, or switches to it from another tab.
  static void chart(BuildContext context, {bool replace = false}) {
    final page = ChartScreen(
      onOpenHome: () => home(context),
      onOpenHistory: () => history(context, replace: true),
      onOpenSettings: () => settings(context, replace: true),
    );
    final nav = Navigator.of(context);
    replace ? nav.pushReplacement(_fade(page)) : nav.push(_fade(page));
  }

  /// Opens History from the Dashboard, or switches to it from another tab.
  static void history(BuildContext context, {bool replace = false}) {
    final page = AlertHistoryScreen(
      onOpenHome: () => home(context),
      onOpenChart: () => chart(context, replace: true),
      onOpenSettings: () => settings(context, replace: true),
    );
    final nav = Navigator.of(context);
    replace ? nav.pushReplacement(_fade(page)) : nav.push(_fade(page));
  }

  /// Opens Settings from the Dashboard, or switches to it from another tab.
  static void settings(BuildContext context, {bool replace = false}) {
    final page = SettingsScreen(
      onOpenHome: () => home(context),
      onOpenChart: () => chart(context, replace: true),
      onOpenHistory: () => history(context, replace: true),
    );
    final nav = Navigator.of(context);
    replace ? nav.pushReplacement(_fade(page)) : nav.push(_fade(page));
  }

  /// Opens the Active Alarm screen for [event] (also handles Alarm Stopped).
  /// "View Alert History" returns to the Dashboard, then opens History.
  static Future<void> alarm(BuildContext context, AlarmEvent event) {
    final nav = Navigator.of(context);
    return nav.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: alarmRouteName),
        fullscreenDialog: true,
        builder: (_) => ActiveAlarmScreen(
          initialEvent: event,
          onBackToDashboard: () => nav.popUntil((r) => r.isFirst),
          onViewHistory: () {
            nav.popUntil((r) => r.isFirst);
            history(nav.context);
          },
        ),
      ),
    );
  }

  static const alarmRouteName = '/active_alarm';
}

/// The Dashboard with Chart/History/Settings wired. USE THIS as the app's `home`.
class DrezaFxHome extends StatelessWidget {
  const DrezaFxHome({super.key});

  @override
  Widget build(BuildContext context) => DashboardScreen(
        onOpenChart: () => DzNav.chart(context),
        onOpenHistory: () => DzNav.history(context),
        onOpenSettings: () => DzNav.settings(context),
      );
}

/// Opens the Active Alarm screen whenever [AlarmGateway.watchActiveAlarm]
/// emits a ringing alarm and none is shown yet. It adds no audio or detection
/// logic. Place it in `MaterialApp.builder`, below [Stage2Services]:
///
/// ```dart
/// MaterialApp(
///   navigatorKey: navKey,
///   builder: (c, child) => AlarmRouteCoordinator(navigatorKey: navKey, child: child!),
///   home: const DrezaFxHome(),
/// )
/// ```
/// The stage-2/screen services must sit ABOVE the MaterialApp.
class AlarmRouteCoordinator extends StatefulWidget {
  const AlarmRouteCoordinator({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AlarmRouteCoordinator> createState() => _AlarmRouteCoordinatorState();
}

class _AlarmRouteCoordinatorState extends State<AlarmRouteCoordinator> {
  StreamSubscription<AlarmEvent?>? _sub;
  AlarmGateway? _gateway;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final g = Stage2Services.of(context).alarms;
    if (_gateway == g) return;
    _gateway = g;
    _sub?.cancel();
    _sub = g.watchActiveAlarm().listen(_onAlarm, onError: (_) {});
  }

  void _onAlarm(AlarmEvent? e) {
    if (e == null || _shown) return;
    final navContext = widget.navigatorKey.currentContext;
    if (navContext == null) return;
    _shown = true;
    DzNav.alarm(navContext, e).whenComplete(() => _shown = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
