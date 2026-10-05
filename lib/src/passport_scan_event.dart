/// Stage of an in-progress passport read.
enum PassportScanStep {
  /// Reader is active and waiting for the passport.
  waitingForTag,

  /// A chip came into range.
  tagDiscovered,

  /// Connected to the chip (also sent after an automatic reconnect).
  tagConnected,

  /// Running PACE or BAC.
  authenticating,
  paceSuccess,
  bacSuccess,
  readingDg1,
  dg1Success,

  /// Reading the portrait; events carry [PassportScanEvent.progress].
  readingDg2,
  dg2Success,

  /// The chip connection dropped. The read is still active: ask the user to
  /// put the phone back on the passport. On Android the read resumes where it
  /// stopped; on iOS the NFC sheet reopens.
  connectionLost,
  completed,
  error,

  /// A step sent by a newer native version this Dart version doesn't know.
  unknown;

  static PassportScanStep fromName(String? name) =>
      PassportScanStep.values.firstWhere((s) => s.name == name, orElse: () => PassportScanStep.unknown);
}

/// Progress update emitted on [BiometricPassportNfc.events] during a read.
class PassportScanEvent {
  final PassportScanStep step;

  /// Human-readable status suitable for showing to the user.
  final String message;

  /// 0–100 for [PassportScanStep.readingDg2], otherwise null.
  final int? progress;

  const PassportScanEvent({required this.step, required this.message, this.progress});

  factory PassportScanEvent.fromMap(Map<dynamic, dynamic> map) => PassportScanEvent(
        step: PassportScanStep.fromName(map['step'] as String?),
        message: (map['message'] as String?) ?? '',
        progress: map['progress'] as int?,
      );

  @override
  String toString() => 'PassportScanEvent(${step.name}, $message${progress == null ? '' : ', $progress%'})';
}
