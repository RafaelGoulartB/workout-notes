enum SleepStageType {
  awake,
  sleeping,
  deep,
  unknown;

  static SleepStageType fromWire(Object? value) {
    return switch (value?.toString()) {
      'awake' => SleepStageType.awake,
      'sleeping' => SleepStageType.sleeping,
      'deep' => SleepStageType.deep,
      _ => SleepStageType.unknown,
    };
  }
}
