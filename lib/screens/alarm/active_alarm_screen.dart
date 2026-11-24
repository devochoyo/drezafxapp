import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../common/format_utils.dart';
import '../common/pair_utils.dart';
import '../contracts/screen_contracts.dart';
import '../contracts/stage2_contracts.dart';

/// Colours of the alarm state (design 07 uses a dark red-tinted background).
const _alarmBg = Color(0xFF1A0B10);
const _alarmPanel = Color(0xFF231920);

/// Short sentence under the pair name. Wording follows design 07 for Entry
/// Level; the others follow the same pattern for the established categories.
String alarmMessageFor(AlertCategory c) {
  switch (c) {
    case AlertCategory.entryLevelReached:
      return 'Price has reached your entry level!';
    case AlertCategory.fairValueGapApproaching:
      return 'Price is approaching your fair value gap!';
    case AlertCategory.fairValueGapReached:
      return 'Price has reached your fair value gap!';
    case AlertCategory.orderBlockApproaching:
      return 'Price is approaching your order block!';
    case AlertCategory.orderBlockReached:
      return 'Price has reached your order block!';
    case AlertCategory.generalPriceTargetReached:
      return 'Price has reached your target!';
  }
}

enum _Phase { ringing, stopped, none }

/// Designs 07 (Active Alarm) and 08 (Alarm Stopped), plus a "no active alarm"
/// state. Data comes ONLY from [AlarmGateway]; stopping calls
/// [AlarmGateway.stopAlarm] (the central audio service) - this screen has no
/// audio logic of its own.
///
/// [initialEvent] is the event the route was opened for; the screen then
/// follows [AlarmGateway.watchActiveAlarm]. If the alarm is stopped elsewhere
/// (stream emits null) the "Alarm Stopped" state is shown.
class ActiveAlarmScreen extends StatefulWidget {
  const ActiveAlarmScreen({
    super.key,
    this.initialEvent,
    this.onBackToDashboard,
    this.onViewHistory,
  });

  final AlarmEvent? initialEvent;
  final VoidCallback? onBackToDashboard;
  final VoidCallback? onViewHistory;

  @override
  State<ActiveAlarmScreen> createState() => _ActiveAlarmScreenState();
}

class _ActiveAlarmScreenState extends State<ActiveAlarmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  AlarmGateway? _alarms;
  StreamSubscription<AlarmEvent?>? _sub;
  AlarmEvent? _event;
  _Phase _phase = _Phase.none;
  DateTime? _silencedAt;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    _phase = _event != null ? _Phase.ringing : _Phase.none;
    if (_phase == _Phase.ringing) _pulse.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_alarms != null) return;
    _alarms = Stage2Services.of(context).alarms;
    _sub = _alarms!.watchActiveAlarm().listen(_onAlarm, onError: (_) {});
  }

  void _onAlarm(AlarmEvent? e) {
    if (!mounted) return;
    if (e != null) {
      // New or updated ringing alarm.
      setState(() {
        _event = e;
        _phase = _Phase.ringing;
        _silencedAt = null;
      });
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_phase == _Phase.ringing && !_stopping) {
      // Stopped from somewhere else (e.g. a notification action).
      _showStopped();
    }
  }

  void _showStopped() {
    _pulse.stop();
    setState(() {
      _phase = _Phase.stopped;
      _silencedAt = DateTime.now(); // the moment the screen learned of the stop
      _stopping = false;
    });
  }

  Future<void> _stop() async {
    if (_stopping || _alarms == null) return;
    setState(() => _stopping = true);
    try {
      await _alarms!.stopAlarm();
      if (mounted) _showStopped();
    } catch (_) {
      if (!mounted) return;
      setState(() => _stopping = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not stop the alarm. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _back() {
    final cb = widget.onBackToDashboard;
    if (cb != null) {
      cb();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While ringing, the system back gesture must not silently leave the
    // screen: the alarm has to be stopped explicitly.
    return PopScope(
      canPop: _phase != _Phase.ringing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.ringing) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Tap STOP ALARM to silence the alarm'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (_phase) {
          _Phase.ringing => _Ringing(
              key: const ValueKey('ringing'),
              event: _event!,
              pulse: _pulse,
              stopping: _stopping,
              onStop: _stop,
            ),
          _Phase.stopped => _Stopped(
              key: const ValueKey('stopped'),
              event: _event,
              silencedAt: _silencedAt,
              onBack: _back,
              onHistory: widget.onViewHistory,
            ),
          _Phase.none => _NoAlarm(
              key: const ValueKey('none'),
              onBack: _back,
            ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design 07
// ---------------------------------------------------------------------------
class _Ringing extends StatelessWidget {
  const _Ringing({
    super.key,
    required this.event,
    required this.pulse,
    required this.stopping,
    required this.onStop,
  });

  final AlarmEvent event;
  final Animation<double> pulse;
  final bool stopping;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _alarmBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Rings(pulse: pulse),
                    const SizedBox(height: 8),
                    Text('PRICE ALERT TRIGGERED!',
                        textAlign: TextAlign.center,
                        style: DzText.sheetTitle().copyWith(fontSize: 22)),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(pairDisplay(event.pair),
                          maxLines: 1,
                          style: DzText.screenTitle().copyWith(fontSize: 44)),
                    ),
                    const SizedBox(height: 8),
                    Text(alarmMessageFor(event.category),
                        textAlign: TextAlign.center,
                        style: DzText.body(
                                color: DzColors.warning, w: FontWeight.w700)
                            .copyWith(fontSize: 16)),
                    const SizedBox(height: 20),
                    _DetailsPanel(
                      background: _alarmPanel,
                      borderColor: DzColors.tint(
                          _alarmPanel, DzColors.danger, 0.45),
                      rows: [
                        _Row('TARGET',
                            formatPrice(event.targetPrice, event.pair)),
                        _Row('TRIGGERED PRICE',
                            formatPrice(event.triggeredPrice, event.pair),
                            valueColor: DzColors.danger),
                        _Row('ALERT TYPE', event.category.label.toUpperCase()),
                        _Row('TRIGGER TIME', formatTimeHms(event.triggeredAt)),
                        _Row('SOUND', soundDisplayName(event.soundFile)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: DzColors.tint(
                                    _alarmBg, DzColors.danger, 0.6),
                                width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                                color: DzColors.danger,
                                shape: BoxShape.circle),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Alarm is playing',
                            style: DzText.body(
                                    color: DzColors.danger,
                                    w: FontWeight.w700)
                                .copyWith(fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StopButton(busy: stopping, onPressed: onStop),
                    const SizedBox(height: 14),
                    Text('Alarm repeats until you stop it',
                        style: DzText.body(color: DzColors.text2)
                            .copyWith(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Stop alarm',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
              color: DzColors.tint(_alarmBg, DzColors.danger, 0.5), width: 2),
        ),
        child: Material(
          color: DzColors.danger,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: busy ? null : onPressed,
            child: SizedBox(
              height: 72,
              width: double.infinity,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text('STOP ALARM',
                              style: DzText.button(color: Colors.white)
                                  .copyWith(fontSize: 26)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Concentric rings + bell. Rings pulse while the alarm rings.
class _Rings extends StatelessWidget {
  const _Rings({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final size = math.min(250.0, w * 0.64);
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          final t = pulse.value;
          final scale = 1 + 0.04 * math.sin(t * 2 * math.pi);
          Widget ring(double f, double alpha, {double border = 1}) =>
              Container(
                width: size * f * scale,
                height: size * f * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DzColors.danger.withAlpha((alpha * 255).round()),
                  border: Border.all(
                      color: DzColors.danger.withAlpha(70), width: border),
                ),
              );
          return Stack(
            alignment: Alignment.center,
            children: [
              ring(1.0, 0.06),
              ring(0.80, 0.10),
              ring(0.60, 0.16),
              Container(
                width: size * 0.40,
                height: size * 0.40,
                decoration: const BoxDecoration(
                    color: DzColors.danger, shape: BoxShape.circle),
                child: Icon(Icons.notifications,
                    color: Colors.white, size: size * 0.22),
              ),
              Positioned(
                top: 0,
                child: Text('FOREX ALERT',
                    style: DzText.caption(color: DzColors.danger)
                        .copyWith(fontSize: 12, letterSpacing: 0.5)),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design 08
// ---------------------------------------------------------------------------
class _Stopped extends StatelessWidget {
  const _Stopped({
    super.key,
    required this.event,
    required this.silencedAt,
    required this.onBack,
    required this.onHistory,
  });

  final AlarmEvent? event;
  final DateTime? silencedAt;
  final VoidCallback onBack;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final e = event;
    return Scaffold(
      backgroundColor: DzColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: DzColors.tint(DzColors.bg, DzColors.accent, 0.08),
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: DzColors.tint(
                                DzColors.bg, DzColors.accent, 0.12),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 74,
                            height: 74,
                            decoration: const BoxDecoration(
                                color: DzColors.accent,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check,
                                size: 40, color: DzColors.onAccent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text('Alarm Stopped', style: DzText.screenTitle()),
                      const SizedBox(height: 8),
                      Text('The repeating alarm has been silenced.',
                          textAlign: TextAlign.center,
                          style: DzText.body(color: DzColors.text2)
                              .copyWith(fontSize: 15)),
                      const SizedBox(height: 28),
                      if (e != null)
                        _DetailsPanel(
                          background: DzColors.card,
                          borderColor: DzColors.border,
                          rows: [
                            _Row('CURRENCY PAIR', pairDisplay(e.pair)),
                            _Row('TARGET', formatPrice(e.targetPrice, e.pair)),
                            _Row('TRIGGERED PRICE',
                                formatPrice(e.triggeredPrice, e.pair)),
                            if (silencedAt != null)
                              _Row('SILENCED AT', formatTimeHms(silencedAt!),
                                  valueColor: DzColors.accent),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DzPrimaryButton(
                  label: 'Back to Dashboard', height: 56, onPressed: onBack),
              if (onHistory != null) ...[
                const SizedBox(height: 12),
                DzSecondaryButton(
                    label: 'View Alert History',
                    height: 56,
                    onPressed: onHistory),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "No active alarm" state (reached if the screen is opened with no alarm).
// ---------------------------------------------------------------------------
class _NoAlarm extends StatelessWidget {
  const _NoAlarm({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DzColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: DzColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: DzColors.border),
                        ),
                        child: const Icon(Icons.notifications_off_outlined,
                            size: 42, color: DzColors.text2),
                      ),
                      const SizedBox(height: 20),
                      Text('No active alarm',
                          style: DzText.sheetTitle().copyWith(fontSize: 22)),
                      const SizedBox(height: 8),
                      Text('There is no alarm ringing right now.',
                          textAlign: TextAlign.center,
                          style: DzText.body(color: DzColors.text2)),
                    ],
                  ),
                ),
              ),
              DzPrimaryButton(
                  label: 'Back to Dashboard', height: 56, onPressed: onBack),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared details panel
// ---------------------------------------------------------------------------
class _Row {
  const _Row(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({
    required this.rows,
    required this.background,
    required this.borderColor,
  });

  final List<_Row> rows;
  final Color background;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: DzColors.border.withAlpha(150)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Text(rows[i].label,
                      style: DzText.label().copyWith(letterSpacing: 0.2)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DzText.body(
                              color: rows[i].valueColor ?? DzColors.text,
                              w: FontWeight.w700)
                          .copyWith(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
