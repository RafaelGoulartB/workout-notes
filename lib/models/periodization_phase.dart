class PeriodizationPhase {
  final String id;
  final String planId;
  final String name;
  final String? templateKey;
  final int color;
  final DateTime startDate;
  final DateTime endDate;
  final String? intent;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PeriodizationPhase({
    required this.id,
    required this.planId,
    required this.name,
    this.templateKey,
    required this.color,
    required this.startDate,
    required this.endDate,
    this.intent,
    required this.orderIndex,
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalDays => endDate.difference(startDate).inDays + 1;
  int get totalWeeks => (totalDays / 7).ceil();

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(startDate) && !day.isAfter(endDate);
  }

  int weekAt(DateTime date) {
    if (date.isBefore(startDate)) return 0;
    return (date.difference(startDate).inDays ~/ 7 + 1).clamp(1, totalWeeks);
  }

  double progressAt(DateTime date) {
    if (date.isBefore(startDate)) return 0;
    if (date.isAfter(endDate)) return 1;
    return ((date.difference(startDate).inDays + 1) / totalDays).clamp(0, 1);
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'plan_id': planId,
    'name': name,
    'template_key': templateKey,
    'color': color,
    'start_date': _date(startDate),
    'end_date': _date(endDate),
    'intent': intent,
    'order_index': orderIndex,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory PeriodizationPhase.fromMap(Map<String, dynamic> map) =>
      PeriodizationPhase(
        id: map['id'] as String,
        planId: map['plan_id'] as String,
        name: map['name'] as String,
        templateKey: map['template_key'] as String?,
        color: (map['color'] as num).toInt(),
        startDate: DateTime.parse(map['start_date'] as String),
        endDate: DateTime.parse(map['end_date'] as String),
        intent: map['intent'] as String?,
        orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}
