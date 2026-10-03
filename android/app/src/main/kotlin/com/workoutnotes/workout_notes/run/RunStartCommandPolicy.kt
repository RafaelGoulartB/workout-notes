package com.workoutnotes.workout_notes.run

/**
 * Pure rules for [RunTrackingService.onStartCommand].
 *
 * A start through `startForegroundService` must be answered by `startForeground`
 * within seconds, even when the service then has nothing to record and stops
 * itself; otherwise Android kills the app with
 * `ForegroundServiceDidNotStartInTimeException`.
 */
object RunStartCommandPolicy {
    /**
     * True for the commands the app sends with `startForegroundService` (run
     * start and restore) and for a null/unknown action (the system restarting a
     * sticky service). Pause/lap/resume/stop/discard come from notification
     * actions (`PendingIntent.getService`), so they never owe a foreground call.
     */
    fun requiresForeground(action: String?): Boolean = when (action) {
        RunTrackingService.ACTION_PAUSE,
        RunTrackingService.ACTION_RESUME,
        RunTrackingService.ACTION_LAP,
        RunTrackingService.ACTION_STOP,
        RunTrackingService.ACTION_DISCARD,
        -> false
        else -> true
    }

    /** An idle service must not stay alive (nor be restarted by the system). */
    fun shouldStayAlive(runActive: Boolean): Boolean = runActive
}
