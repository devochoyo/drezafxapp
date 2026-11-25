import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Debug-only HUD showing frame build / raster times.
/// Off by default — set [kChartPerfHud] to true to enable.
const bool kChartPerfHud = false;

class ChartPerfOverlay extends StatefulWidget {
  const ChartPerfOverlay({super.key});

  @override
  State<ChartPerfOverlay> createState() => _ChartPerfOverlayState();
}

class _ChartPerfOverlayState extends State<ChartPerfOverlay> {
  double _buildMs = 0;
  double _rasterMs = 0;

  @override
  void initState() {
    super.initState();
    if (kChartPerfHud && kDebugMode) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    }
  }

  @override
  void dispose() {
    if (kChartPerfHud && kDebugMode) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    final t = timings.last;
    setState(() {
      _buildMs = t.buildDuration.inMicroseconds / 1000.0;
      _rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kChartPerfHud || !kDebugMode) return const SizedBox.shrink();
    return Positioned(
      top: 4,
      left: 4,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: const Color(0xAA000000),
          child: Text(
            'build ${_buildMs.toStringAsFixed(1)} ms  '
            'raster ${_rasterMs.toStringAsFixed(1)} ms',
            style: const TextStyle(
              color: Color(0xFF00FF88),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
