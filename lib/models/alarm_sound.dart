/// The six selectable alarm sounds (fixed by the UI design).
///
/// Each file is a complete alarm cycle: bell → spoken announcement → bell →
/// spoken announcement. It starts directly on the first bell strike, so
/// looping the file gives the required continuous sequence.
enum AlarmSound {
  entryLevelReached(
    fileName: 'entry_level_reached.wav',
    label: 'Entry Level Reached',
    description: 'Highest-pitched bell, fast double ring. Most urgent.',
  ),
  fvgApproaching(
    fileName: 'fvg_approaching.wav',
    label: 'Fair Value Gap Approaching',
    description: 'One slower, lower, gentler ring. Early warning.',
  ),
  fvgReached(
    fileName: 'fvg_reached.wav',
    label: 'Fair Value Gap Reached',
    description: 'Three fast short rings. Stronger than approaching.',
  ),
  orderBlockApproaching(
    fileName: 'order_block_approaching.wav',
    label: 'Order Block Approaching',
    description: 'Two slow rings in a lower register. Early warning.',
  ),
  orderBlockReached(
    fileName: 'order_block_reached.wav',
    label: 'Order Block Reached',
    description: 'Three rings climbing in pitch. Most distinctive.',
  ),
  generalTargetReached(
    fileName: 'general_target_reached.wav',
    label: 'General Price Target Reached',
    description: 'One steady classic alarm-clock ring.',
  );

  const AlarmSound({
    required this.fileName,
    required this.label,
    required this.description,
  });

  /// File name inside `assets/sounds/` (unchanged from the supplied files).
  final String fileName;

  /// Name shown in the sound-selection UI.
  final String label;

  /// One-line description for the sound-selection UI.
  final String description;

  /// Path as declared in pubspec.yaml.
  String get assetPath => 'assets/sounds/$fileName';

  /// Path relative to `assets/`, as expected by audioplayers' `AssetSource`.
  String get audioSourcePath => 'sounds/$fileName';

  /// Standalone 1.2 s bell supplied with the sound pack. It is declared in
  /// pubspec.yaml but not part of the six selectable sounds.
  static const String standaloneBellFileName = 'forex_alarm_bell.wav';
}
