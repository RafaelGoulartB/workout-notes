import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/repositories/run_repository.dart';

void main() {
  test('builds a review preview without importing the spool', () {
    final spool = <String, dynamic>{
      'activity': <String, dynamic>{
        'id': 'review-1',
        'status': 'pending_review',
        'started_at': '2026-08-25T10:00:00.000Z',
        'ended_at': '2026-08-25T10:20:00.000Z',
        'duration_seconds': 1200,
        'moving_time_seconds': 1150,
        'distance_meters': 3200.0,
        'plan_workout_id': 'workout-1',
        'scheduled_run_id': 'scheduled-1',
        'splits': <Map<String, dynamic>>[
          <String, dynamic>{
            'km': 1,
            'distance_meters': 1000.0,
            'duration_seconds': 350,
            'pace_sec_per_km': 350.0,
            'is_partial': false,
          },
        ],
        'voice_step_results': <Map<String, dynamic>>[
          <String, dynamic>{
            'sequence': 0,
            'role': 'work',
            'repIndex': 1,
            'plannedMetric': 'distance',
            'plannedValue': 1000,
            'distanceMeters': 1000.0,
            'durationSeconds': 350,
          },
        ],
      },
      'points': <Map<String, dynamic>>[],
    };

    final preview = RunRepository().previewNativeSpool(spool);
    final draft = RunReviewDraft.fromSpool(activity: preview, spool: spool);

    expect(preview.status, 'completed');
    expect(draft.id, 'review-1');
    expect(draft.planWorkoutId, 'workout-1');
    expect(draft.scheduledRunId, 'scheduled-1');
    expect(draft.splits.single.paceSecPerKm, 350);
    expect(draft.stepResults.single.actualPaceSecPerKm, 350);
  });
}
