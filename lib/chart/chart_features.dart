import 'alarm/alarm_feature.dart';
import 'contracts/chart_contracts.dart';
import 'drawing/drawing_feature.dart';

/// Feature registry used by [ChartScreen].
///
/// Registered by Batch 5 (merge):
///   AlarmChartFeature  — B3
///   DrawingChartFeature — B4
List<ChartFeature> createChartFeatures() => <ChartFeature>[
      AlarmChartFeature(),
      DrawingChartFeature(),
    ];
