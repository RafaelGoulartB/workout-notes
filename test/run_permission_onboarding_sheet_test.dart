import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_permission_state.dart';
import 'package:workout_notes/widgets/run/run_permission_onboarding_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'explains permissions and allows continuing without notifications',
    (tester) async {
      var permissionState = const RunPermissionState(
        locationGranted: false,
        notificationsGranted: false,
        notificationsPermissionRequired: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RunPermissionOnboardingSheet(
              initialState: permissionState,
              onRefresh: () async => permissionState,
              onRequestLocation: () async {
                permissionState = permissionState.copyWith(
                  locationGranted: true,
                );
                return true;
              },
              onRequestNotifications: () async => false,
              onOpenSettings: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Permissões para a corrida'), findsOneWidget);
      expect(find.textContaining('“o tempo todo”'), findsOneWidget);
      expect(
        find.byKey(const Key('run-permission-location-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('run-permission-notification-action')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('run-permission-continue')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('run-permission-location-action')),
      );
      await tester.tap(find.byKey(const Key('run-permission-location-action')));
      await tester.pumpAndSettle();

      expect(find.text('Permitida'), findsOneWidget);
      expect(find.text('Continuar sem notificações'), findsOneWidget);
    },
  );

  testWidgets('notification denial is non-blocking and exposes app settings', (
    tester,
  ) async {
    const permissionState = RunPermissionState(
      locationGranted: true,
      notificationsGranted: false,
      notificationsPermissionRequired: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RunPermissionOnboardingSheet(
            initialState: permissionState,
            onRefresh: () async => permissionState,
            onRequestLocation: () async => true,
            onRequestNotifications: () async => false,
            onOpenSettings: () async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('run-permission-notification-action')),
    );
    await tester.tap(
      find.byKey(const Key('run-permission-notification-action')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Você ainda pode gravar a corrida'),
      findsOneWidget,
    );
    expect(find.text('Abrir configurações'), findsOneWidget);
    expect(find.text('Continuar sem notificações'), findsOneWidget);
  });
}
