enum PeriodizationPlanStatus {
  draft('draft'),
  active('active'),
  completed('completed'),
  archived('archived');

  final String value;
  const PeriodizationPlanStatus(this.value);

  static PeriodizationPlanStatus fromString(String? value) => values.firstWhere(
    (status) => status.value == value,
    orElse: () => PeriodizationPlanStatus.draft,
  );
}

class PeriodizationPlan {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final PeriodizationPlanStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PeriodizationPlan({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalDays => endDate.difference(startDate).inDays + 1;

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(startDate) && !day.isAfter(endDate);
  }

  double progressAt(DateTime date) {
    if (date.isBefore(startDate)) return 0;
    if (date.isAfter(endDate)) return 1;
    return ((date.difference(startDate).inDays + 1) / totalDays).clamp(0, 1);
  }

  PeriodizationPlan copyWith({
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    PeriodizationPlanStatus? status,
    Object? notes = _sentinel,
    DateTime? updatedAt,
  }) => PeriodizationPlan(
    id: id,
    name: name ?? this.name,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    status: status ?? this.status,
    notes: identical(notes, _sentinel) ? this.notes : notes as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'start_date': _date(startDate),
    'end_date': _date(endDate),
    'status': status.value,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory PeriodizationPlan.fromMap(Map<String, dynamic> map) =>
      PeriodizationPlan(
        id: map['id'] as String,
        name: map['name'] as String,
        startDate: DateTime.parse(map['start_date'] as String),
        endDate: DateTime.parse(map['end_date'] as String),
        status: PeriodizationPlanStatus.fromString(map['status'] as String?),
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}

const Object _sentinel = Object();
