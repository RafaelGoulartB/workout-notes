import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/services/sleep_goal_service.dart';
import 'support/test_db.dart';

void main() {

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    await installTestDb();
  });

  tearDown(uninstallTestDb);

  test('loads the default and persists normalized 15-minute goals', () async {
    final service = SleepGoalService();

    expect(await service.load(), SleepGoalService.defaultGoalMinutes);

    await service.save(601);
    expect(await service.load(), 600);

    await service.save(1000);
    expect(await service.load(), SleepGoalService.maximumGoalMinutes);
  });
}
