enum CardioActivityType {
  running('running'),
  stationaryBike('stationary_bike'),
  treadmill('treadmill');

  final String databaseValue;

  const CardioActivityType(this.databaseValue);

  /// Running outdoors or on a treadmill: counts toward running stats,
  /// records and plans.
  bool get isRunning => this == running || this == treadmill;

  /// Recorded with an in-app timer (no GPS); distance is entered on review.
  bool get isIndoor => this == stationaryBike || this == treadmill;

  bool get usesGps => this == running;

  static CardioActivityType fromDatabase(Object? value) {
    return CardioActivityType.values.firstWhere(
      (type) => type.databaseValue == value,
      orElse: () => CardioActivityType.running,
    );
  }
}
