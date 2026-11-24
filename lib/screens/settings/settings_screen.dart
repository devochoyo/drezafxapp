import 'dart:async';
import 'package:flutter/material.dart';
import '../common/dz_theme.dart';
import '../common/dz_widgets.dart';
import '../contracts/screen_contracts.dart';
import '../contracts/stage2_contracts.dart';
import '../sound_selection/sound_selection_screen.dart';
import 'market_data_setup_screen.dart';

/// Design 12. Only the controls shown in the design are present. Persisted
/// values go through [SettingsGateway]; the screen has no storage of its own.
/// Sound preview uses the shared [SoundGateway] (central audio service).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onOpenHome, this.onOpenHistory});

  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenHistory;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsGateway? _settings;
  SoundGateway? _sounds;
  StreamSubscription<AppSettings>? _settingsSub;
  StreamSubscription<SystemStatus>? _statusSub;
  StreamSubscription<MarketDataSetup>? _setupSub;
  MarketDataSetup? _setup;
  StreamSubscription<String?>? _previewSub;

  AppSettings? _s;
  SystemStatus? _status;
  Object? _error;
  String? _previewing;
  String _version = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings != null) return;
    _settings = Stage2Services.of(context).settings;
    _sounds = ScreenServices.of(context).sounds;
    _settingsSub = _settings!.watchSettings().listen(
      (v) {
        if (mounted) setState(() => _s = v);
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e);
      },
    );
    _statusSub = _settings!.watchSystemStatus().listen(
      (v) {
        if (mounted) setState(() => _status = v);
      },
      onError: (_) {},
    );
    _setupSub = _settings!.watchMarketDataSetup().listen(
      (v) {
        if (mounted) setState(() => _setup = v);
      },
      onError: (_) {},
    );
    _previewSub = _sounds!.previewingFile.listen((f) {
      if (mounted) setState(() => _previewing = f);
    });
    _settings!.appVersion().then((v) {
      if (mounted) setState(() => _version = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _statusSub?.cancel();
    _setupSub?.cancel();
    _previewSub?.cancel();
    _sounds?.stopPreview();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  Future<void> _run(Future<void> Function() f, String failMsg) async {
    try {
      await f();
    } catch (_) {
      if (mounted) _snack(failMsg);
    }
  }

  Future<void> _pickSound() async {
    final s = _s;
    if (s == null) return;
    final picked =
        await showSoundSelectionSheet(context, selectedFile: s.defaultSoundFile);
    if (picked != null && picked != s.defaultSoundFile && mounted) {
      await _run(() => _settings!.setDefaultSoundFile(picked),
          'Could not save the default sound');
    }
  }

  Future<void> _togglePreview() async {
    final s = _s;
    if (s == null) return;
    try {
      if (_previewing == s.defaultSoundFile) {
        await _sounds!.stopPreview();
      } else {
        await _sounds!.preview(s.defaultSoundFile);
      }
    } catch (_) {
      if (mounted) _snack('Could not play this sound');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final st = _status;
    Widget content;
    if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Could not load settings.',
              style: DzText.body(color: DzColors.text2)),
        ),
      );
    } else if (s == null) {
      content = const Center(
          child: CircularProgressIndicator(color: DzColors.accent));
    } else {
      content = ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          const _SectionLabel('MARKET DATA'),
          _Group(children: [
            _ValueRow(
              label: 'Price provider (OANDA)',
              value: _setup == null
                  ? '—'
                  : (_setup!.hasCredentials ? 'Set up' : 'Not set up'),
              valueColor: _setup?.hasCredentials == true
                  ? DzColors.accent
                  : DzColors.warning,
              chevron: true,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const MarketDataSetupScreen())),
            ),
          ]),
          const _SectionLabel('NOTIFICATIONS'),
          _Group(children: [
            _SwitchRow(
              label: 'Enable notifications',
              value: s.notificationsEnabled,
              onChanged: (v) => _run(
                  () => _settings!.setNotificationsEnabled(v),
                  'Could not change notifications'),
            ),
            _ValueRow(
              label: 'Notification permission',
              value: _permissionText(st),
              valueColor: _permissionColor(st),
              onTap: st?.notificationPermission == NotificationPermission.denied
                  ? () => _run(_settings!.requestNotificationPermission,
                      'Could not request permission')
                  : null,
            ),
          ]),
          const _SectionLabel('ALARM'),
          _Group(children: [
            _ValueRow(
              label: 'Default alarm sound',
              value: soundDisplayName(s.defaultSoundFile),
              chevron: true,
              onTap: _pickSound,
            ),
            _SwitchRow(
              label: 'Vibration',
              value: s.vibrationEnabled,
              onChanged: (v) => _run(() => _settings!.setVibrationEnabled(v),
                  'Could not change vibration'),
            ),
            // The repeating behaviour is fixed by the Master Specification
            // (repeat until stopped); there is no other option to choose.
            _ValueRow(
              label: 'Alarm playback',
              value: 'Repeat until stopped',
              chevron: true,
              onTap: _showPlaybackInfo,
            ),
            _Row(
              label: 'Sound preview',
              trailing: DzPreviewButton(
                playing: _previewing == s.defaultSoundFile,
                size: 36,
                onPressed: _togglePreview,
              ),
            ),
          ]),
          const _SectionLabel('BACKGROUND MONITORING'),
          _Group(children: [
            _ValueRow(
              label: 'Monitoring status',
              value: st == null
                  ? '—'
                  : (st.monitoringActive ? 'Active' : 'Inactive'),
              valueColor: st == null
                  ? DzColors.text2
                  : (st.monitoringActive ? DzColors.accent : DzColors.text2),
            ),
            _ValueRow(
              label: 'Background service',
              value: st == null
                  ? '—'
                  : (st.backgroundServiceRunning ? 'Running' : 'Not running'),
              valueColor: st == null
                  ? DzColors.text2
                  : (st.backgroundServiceRunning
                      ? DzColors.accent
                      : DzColors.warning),
            ),
            _ValueRow(
              label: 'Battery optimization',
              value: _batteryText(st),
              valueColor: _batteryColor(st),
              onTap: () => _run(_settings!.openBatterySettings,
                  'Could not open battery settings'),
            ),
            _ValueRow(
              label: 'Internet connection',
              value: st?.internetConnected == null
                  ? '—'
                  : (st!.internetConnected! ? 'Connected' : 'Not connected'),
              valueColor: st?.internetConnected == true
                  ? DzColors.accent
                  : (st?.internetConnected == false
                      ? DzColors.danger
                      : DzColors.text2),
            ),
          ]),
          const _SectionLabel('APPLICATION'),
          _Group(children: [
            _ValueRow(
                label: 'Version', value: _version.isEmpty ? '—' : _version),
            _ValueRow(
              label: 'About Forex Alert',
              value: '',
              chevron: true,
              onTap: _showAbout,
            ),
          ]),
        ],
      );
    }

    return Scaffold(
      backgroundColor: DzColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text('Settings', style: DzText.screenTitle()),
              ),
            ),
            Expanded(child: content),
            DzBottomNav(
              currentIndex: 2,
              onHome: widget.onOpenHome,
              onHistory: widget.onOpenHistory,
            ),
          ],
        ),
      ),
    );
  }

  String _permissionText(SystemStatus? st) {
    switch (st?.notificationPermission) {
      case NotificationPermission.granted:
        return 'Granted';
      case NotificationPermission.denied:
        return 'Not granted';
      default:
        return '—';
    }
  }

  Color _permissionColor(SystemStatus? st) {
    switch (st?.notificationPermission) {
      case NotificationPermission.granted:
        return DzColors.accent;
      case NotificationPermission.denied:
        return DzColors.warning;
      default:
        return DzColors.text2;
    }
  }

  String _batteryText(SystemStatus? st) {
    switch (st?.battery) {
      case BatteryOptimization.unrestricted:
        return 'Unrestricted';
      case BatteryOptimization.optimized:
        return 'Set to Unrestricted';
      default:
        return '—';
    }
  }

  Color _batteryColor(SystemStatus? st) {
    switch (st?.battery) {
      case BatteryOptimization.unrestricted:
        return DzColors.accent;
      case BatteryOptimization.optimized:
        return DzColors.warning;
      default:
        return DzColors.text2;
    }
  }

  Future<void> _showPlaybackInfo() => showDzInfoDialog(
        context,
        icon: Icons.repeat,
        title: 'Alarm playback',
        message: 'When a price alert triggers, the alarm sound repeats until '
            'you open the app and tap STOP ALARM.',
      );

  Future<void> _showAbout() => showDzInfoDialog(
        context,
        icon: Icons.notifications,
        title: 'About Forex Alert',
        message: 'DrezaFx watches the forex prices you choose and sounds an '
            'alarm when a target price you entered is crossed.\n\n'
            'Background alarms depend on Android: battery restrictions, '
            'revoked permissions or a lost internet connection can affect '
            'reliability.${_version.isEmpty ? '' : '\n\nVersion $_version'}',
      );
}

/// Small information dialog (same chrome as the delete dialog, one button).
Future<void> showDzInfoDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withAlpha(171),
    builder: (ctx) => Dialog(
      backgroundColor: DzColors.elevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 337),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      DzColors.tint(DzColors.elevated, DzColors.accent, 0.2),
                ),
                child: Icon(icon, color: DzColors.accent, size: 26),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center, style: DzText.sheetTitle()),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: DzText.body(color: DzColors.text2)
                      .copyWith(fontSize: 14.5, height: 1.4)),
              const SizedBox(height: 20),
              DzPrimaryButton(
                  label: 'OK', height: 46, onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Row building blocks
// ---------------------------------------------------------------------------
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        child: Text(text, style: DzText.caption(letterSpacing: 0.6)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: DzColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DzColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: DzColors.border.withAlpha(150)),
              children[i],
            ],
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.trailing, this.onTap});
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: DzText.body().copyWith(fontSize: 16)),
                ),
                trailing,
              ],
            ),
          ),
        ),
      );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.chevron = false,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(label,
                      style: DzText.body().copyWith(fontSize: 16)),
                ),
                if (value.isNotEmpty)
                  Flexible(
                    flex: 3,
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DzText.body(
                              color: valueColor ?? DzColors.text2,
                              w: valueColor == null
                                  ? FontWeight.w400
                                  : FontWeight.w700)
                          .copyWith(fontSize: 14),
                    ),
                  ),
                if (chevron) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right,
                      size: 22, color: DzColors.text2),
                ],
              ],
            ),
          ),
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _Row(
        label: label,
        onTap: () => onChanged(!value),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: DzColors.accent,
          inactiveThumbColor: DzColors.text2,
          inactiveTrackColor: DzColors.elevated,
        ),
      );
}
