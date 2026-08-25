import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_permission_state.dart';

class RunPermissionOnboardingSheet extends StatefulWidget {
  final RunPermissionState initialState;
  final Future<RunPermissionState> Function() onRefresh;
  final Future<bool> Function() onRequestLocation;
  final Future<bool> Function() onRequestNotifications;
  final Future<bool> Function() onOpenSettings;

  const RunPermissionOnboardingSheet({
    super.key,
    required this.initialState,
    required this.onRefresh,
    required this.onRequestLocation,
    required this.onRequestNotifications,
    required this.onOpenSettings,
  });

  @override
  State<RunPermissionOnboardingSheet> createState() =>
      _RunPermissionOnboardingSheetState();
}

class _RunPermissionOnboardingSheetState
    extends State<RunPermissionOnboardingSheet>
    with WidgetsBindingObserver {
  late RunPermissionState _permissionState;
  bool _requestingLocation = false;
  bool _requestingNotifications = false;
  bool _locationRequestFailed = false;
  bool _notificationRequestFailed = false;

  @override
  void initState() {
    super.initState();
    _permissionState = widget.initialState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final refreshed = await widget.onRefresh();
    if (!mounted) return;
    setState(() {
      _permissionState = refreshed;
      if (refreshed.locationGranted) _locationRequestFailed = false;
      if (refreshed.notificationsGranted) {
        _notificationRequestFailed = false;
      }
    });
  }

  Future<void> _requestLocation() async {
    if (_requestingLocation) return;
    setState(() {
      _requestingLocation = true;
      _locationRequestFailed = false;
    });
    final granted = await widget.onRequestLocation();
    final refreshed = await widget.onRefresh();
    if (!mounted) return;
    setState(() {
      _permissionState = refreshed.copyWith(locationGranted: granted);
      _requestingLocation = false;
      _locationRequestFailed = !granted;
    });
  }

  Future<void> _requestNotifications() async {
    if (_requestingNotifications) return;
    setState(() {
      _requestingNotifications = true;
      _notificationRequestFailed = false;
    });
    final granted = await widget.onRequestNotifications();
    final refreshed = await widget.onRefresh();
    if (!mounted) return;
    setState(() {
      _permissionState = refreshed.copyWith(notificationsGranted: granted);
      _requestingNotifications = false;
      _notificationRequestFailed = !granted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final notificationsNeedPermission =
        _permissionState.notificationsNeedAttention;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              loc.runPermissionsTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.runPermissionsIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _PermissionCard(
              icon: Icons.location_on_outlined,
              title: loc.runPermissionsLocationTitle,
              description: loc.runPermissionsLocationBody,
              importanceLabel: loc.runPermissionsRequired,
              granted: _permissionState.locationGranted,
              grantedLabel: loc.runPermissionsAllowed,
              deniedLabel: loc.runPermissionsNotAllowed,
              actionLabel: loc.runRecordGrantPermission,
              actionKey: const Key('run-permission-location-action'),
              requesting: _requestingLocation,
              onAction: _permissionState.locationGranted
                  ? null
                  : _requestLocation,
              error: _locationRequestFailed
                  ? loc.runPermissionsLocationDenied
                  : null,
              onOpenSettings: _locationRequestFailed
                  ? widget.onOpenSettings
                  : null,
              openSettingsLabel: loc.runPermissionsOpenSettings,
            ),
            const SizedBox(height: 12),
            _PermissionCard(
              icon: Icons.notifications_active_outlined,
              title: loc.runPermissionsNotificationsTitle,
              description: loc.runPermissionsNotificationsBody,
              importanceLabel: loc.runPermissionsRecommended,
              granted: _permissionState.notificationsGranted,
              grantedLabel: loc.runPermissionsAllowed,
              deniedLabel: loc.runPermissionsNotAllowed,
              actionLabel: loc.runPermissionsAllowNotifications,
              actionKey: const Key('run-permission-notification-action'),
              requesting: _requestingNotifications,
              onAction: notificationsNeedPermission
                  ? _requestNotifications
                  : null,
              error: _notificationRequestFailed
                  ? loc.runPermissionsNotificationsDenied
                  : null,
              onOpenSettings: _notificationRequestFailed
                  ? widget.onOpenSettings
                  : null,
              openSettingsLabel: loc.runPermissionsOpenSettings,
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(
                  alpha: 0.55,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.privacy_tip_outlined,
                      size: 20,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        loc.runPermissionsForegroundNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_permissionState.locationGranted)
              FilledButton(
                key: const Key('run-permission-continue'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  notificationsNeedPermission
                      ? loc.runPermissionsContinueWithoutNotifications
                      : loc.runPermissionsContinue,
                ),
              )
            else
              TextButton(
                key: const Key('run-permission-later'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(loc.runPermissionsLater),
              ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String importanceLabel;
  final bool granted;
  final String grantedLabel;
  final String deniedLabel;
  final String actionLabel;
  final Key actionKey;
  final bool requesting;
  final VoidCallback? onAction;
  final String? error;
  final Future<bool> Function()? onOpenSettings;
  final String openSettingsLabel;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.importanceLabel,
    required this.granted,
    required this.grantedLabel,
    required this.deniedLabel,
    required this.actionLabel,
    required this.actionKey,
    required this.requesting,
    required this.onAction,
    required this.error,
    required this.onOpenSettings,
    required this.openSettingsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = granted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        importanceLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    granted ? grantedLabel : deniedLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: actionKey,
                onPressed: requesting ? null : onAction,
                child: requesting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(actionLabel),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              if (onOpenSettings != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onOpenSettings,
                    child: Text(openSettingsLabel),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
