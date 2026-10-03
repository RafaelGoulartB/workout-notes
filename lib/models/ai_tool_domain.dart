/// Data domains the AI Coach can read or propose changes to. The user can
/// switch off a domain in the AI settings; its tools then leave the catalog
/// (the catalog only changes when the setting changes, so the provider's
/// prompt cache stays warm across turns).
enum AiToolDomain {
  /// Always on: memory and other coach-internal tools.
  core,
  workouts,
  running,
  sleep,
  nutrition,
  body,
  goals,
  planning;

  /// Domains the user can switch off (everything except [core]).
  static const List<AiToolDomain> optional = [
    workouts,
    running,
    sleep,
    nutrition,
    body,
    goals,
    planning,
  ];

  String get storageKey => name;

  static AiToolDomain? fromStorageKey(String? value) {
    for (final domain in values) {
      if (domain.name == value) return domain;
    }
    return null;
  }
}
