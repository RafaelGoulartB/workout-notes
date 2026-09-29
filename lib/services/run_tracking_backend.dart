import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/run_tracking_state.dart';

/// What a [RunTrackingBackend] can do to the service that owns it.
abstract class RunTrackingSink {
  /// The state last published to the UI.
  RunTrackingState get state;

  /// The plan/goal identity picked for the session being started.
  RunSessionContext? get sessionContext;

  /// Replaces the UI state and notifies listeners.
  void publish(RunTrackingState state);

  void reportError(String code, String message);
}

/// The run tracker behind `RunTrackingService`: it executes session commands
/// and publishes state through its [RunTrackingSink].
///
/// Production uses `NativeRunTrackingBackend` (the Android foreground
/// service). Debug builds can swap in `RunDebugBackend` to fake a GPS run, so
/// the service itself has no simulator branches.
abstract class RunTrackingBackend {
  /// True for a backend that fabricates the run instead of measuring it. Its
  /// review stays in memory because no native spool exists.
  bool get isSimulated;

  /// Starts recording. Returns whether a run is now active.
  Future<bool> start();

  Future<void> pause();

  Future<void> resume();

  /// Marks a manual lap. Returns the lap just closed, or null when it was
  /// ignored (accidental double tap, nothing recording).
  Future<RunLap?> lap();

  /// Ends the run and returns its spool payload with the activity in
  /// `pending_review`, or null when there is nothing to review.
  Future<Map<String, dynamic>?> stopForReview();

  /// Drops the run without keeping anything.
  Future<void> discard();

  void dispose();
}
