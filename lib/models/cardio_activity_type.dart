enum CardioActivityType {
  running('running'),
  stationaryBike('stationary_bike');

  final String databaseValue;

  const CardioActivityType(this.databaseValue);

  static CardioActivityType fromDatabase(Object? value) {
    return CardioActivityType.values.firstWhere(
      (type) => type.databaseValue == value,
      orElse: () => CardioActivityType.running,
    );
  }
}
