package com.workoutnotes.workout_notes.common

/**
 * What to do with an alarm found due (or ringing) when its schedule is
 * restored after a reboot, an update or an app launch.
 *
 * Android 15+ forbids a BOOT_COMPLETED receiver from starting the
 * `mediaPlayback` foreground services that ring, so a due alarm is never
 * started from there: it is re-armed as an exact alarm just past the boot
 * allowlist window, and that alarm's own receiver (exempt from the
 * background start limits) rings it.
 */
object AlarmRestorePolicy {
    const val REARM_DELAY_MILLIS = 3_000L

    /**
     * After a boot the app stays temporarily allowlisted for
     * `boot_time_temp_allowlist_duration` (20 s by default), and a foreground
     * service started in that window still counts as started from
     * BOOT_COMPLETED, even from an exact alarm. Re-arming past it lets the
     * alarm's own exemption apply.
     */
    const val BOOT_REARM_DELAY_MILLIS = 30_000L

    /** An alarm missed by more than this is no longer worth ringing late. */
    const val MAX_LATE_RING_MILLIS = 2L * 60L * 60L * 1_000L

    fun shouldRingLate(alarmAtMillis: Long, nowMillis: Long): Boolean =
        nowMillis - alarmAtMillis <= MAX_LATE_RING_MILLIS

    fun rearmAt(nowMillis: Long, afterBoot: Boolean = false): Long =
        nowMillis + if (afterBoot) BOOT_REARM_DELAY_MILLIS else REARM_DELAY_MILLIS
}
