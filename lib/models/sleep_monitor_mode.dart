/// The way a sleep monitoring session is finished.
enum SleepMonitoringMode {
  alarmWithoutMission('alarm_without_mission'),
  alarmWithMission('alarm_with_mission'),
  monitoringOnly('monitoring_only');

  const SleepMonitoringMode(this.wireValue);

  final String wireValue;

  bool get hasAlarm => this != monitoringOnly;
  bool get requiresMission => this == alarmWithMission;

  static SleepMonitoringMode fromWire(Object? value) {
    return values.firstWhere(
      (mode) => mode.wireValue == value,
      orElse: () => alarmWithoutMission,
    );
  }
}

enum SleepMissionStatus {
  unconfigured('unconfigured'),
  ready('ready'),
  pending('pending'),
  completed('completed');

  const SleepMissionStatus(this.wireValue);

  final String wireValue;

  static SleepMissionStatus fromWire(Object? value) {
    return values.firstWhere(
      (status) => status.wireValue == value,
      orElse: () => unconfigured,
    );
  }
}

/// The locally stored mission metadata. The barcode value itself is never
/// persisted by Flutter; [hash] and [salt] are used for equality checks only.
class SleepMissionConfig {
  final bool enabled;
  final String type;
  final String? hash;
  final String? salt;
  final String? format;
  final DateTime? registeredAt;

  const SleepMissionConfig({
    required this.enabled,
    this.type = 'barcode',
    this.hash,
    this.salt,
    this.format,
    this.registeredAt,
  });

  const SleepMissionConfig.empty()
    : enabled = false,
      type = 'barcode',
      hash = null,
      salt = null,
      format = null,
      registeredAt = null;

  /// The code remains registered when the global switch is off.
  bool get isConfigured =>
      type == 'barcode' &&
      hash != null &&
      hash!.isNotEmpty &&
      salt != null &&
      salt!.isNotEmpty &&
      format != null &&
      format!.isNotEmpty;

  bool get isReady => enabled && isConfigured;

  SleepMissionStatus get status =>
      isReady ? SleepMissionStatus.ready : SleepMissionStatus.unconfigured;

  SleepMissionConfig copyWith({
    bool? enabled,
    String? type,
    String? hash,
    String? salt,
    String? format,
    DateTime? registeredAt,
    bool clearBarcode = false,
  }) {
    return SleepMissionConfig(
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
      hash: clearBarcode ? null : (hash ?? this.hash),
      salt: clearBarcode ? null : (salt ?? this.salt),
      format: clearBarcode ? null : (format ?? this.format),
      registeredAt: clearBarcode ? null : (registeredAt ?? this.registeredAt),
    );
  }

  Map<String, dynamic> toSettings() => {
    'sleep_mission_enabled': enabled ? 'true' : 'false',
    'sleep_mission_type': type,
    'sleep_mission_barcode_hash': hash ?? '',
    'sleep_mission_barcode_salt': salt ?? '',
    'sleep_mission_barcode_format': format ?? '',
    'sleep_mission_registered_at': registeredAt?.toIso8601String() ?? '',
  };

  factory SleepMissionConfig.fromSettings(Map<String, String> settings) {
    final registeredText = settings['sleep_mission_registered_at'];
    return SleepMissionConfig(
      enabled: settings['sleep_mission_enabled'] == 'true',
      type: settings['sleep_mission_type'] ?? 'barcode',
      hash: _nonEmpty(settings['sleep_mission_barcode_hash']),
      salt: _nonEmpty(settings['sleep_mission_barcode_salt']),
      format: _nonEmpty(settings['sleep_mission_barcode_format']),
      registeredAt: registeredText == null || registeredText.isEmpty
          ? null
          : DateTime.tryParse(registeredText),
    );
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
