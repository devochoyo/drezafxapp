import 'package:flutter/material.dart';
import '../contracts/screen_contracts.dart';
import 'dz_theme.dart';

/// Colour used for a category's bell tile and caption on the Dashboard card.
/// Design shows: Entry = green, Approaching = amber, Order Block Reached =
/// blue, General = grey. Fair Value Gap Reached is not visible in the designs;
/// blue is used (documented as an interpretation in HANDOVER.md).
Color categoryColor(AlertCategory c) {
  switch (c) {
    case AlertCategory.entryLevelReached:
      return DzColors.accent;
    case AlertCategory.fairValueGapApproaching:
    case AlertCategory.orderBlockApproaching:
      return DzColors.warning;
    case AlertCategory.fairValueGapReached:
    case AlertCategory.orderBlockReached:
      return DzColors.accent2;
    case AlertCategory.generalPriceTargetReached:
      return DzColors.text2;
  }
}
