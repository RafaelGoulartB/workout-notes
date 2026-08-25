class RunPermissionState {
  final bool locationGranted;
  final bool notificationsGranted;
  final bool notificationsPermissionRequired;

  const RunPermissionState({
    required this.locationGranted,
    required this.notificationsGranted,
    required this.notificationsPermissionRequired,
  });

  bool get notificationsNeedAttention =>
      notificationsPermissionRequired && !notificationsGranted;

  RunPermissionState copyWith({
    bool? locationGranted,
    bool? notificationsGranted,
    bool? notificationsPermissionRequired,
  }) {
    return RunPermissionState(
      locationGranted: locationGranted ?? this.locationGranted,
      notificationsGranted: notificationsGranted ?? this.notificationsGranted,
      notificationsPermissionRequired:
          notificationsPermissionRequired ??
          this.notificationsPermissionRequired,
    );
  }
}
