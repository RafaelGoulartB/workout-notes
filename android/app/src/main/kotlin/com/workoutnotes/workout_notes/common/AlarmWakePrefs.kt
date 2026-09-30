package com.workoutnotes.workout_notes.common

import android.content.Context
import android.media.AudioManager

/**
 * Wake-up sound settings mirrored from Flutter (the gentle volume rise and the
 * final boost), readable while the app is closed, plus the alarm volume saved
 * before a boost so it can be restored even after a crash or a reboot.
 */
object AlarmWakePrefs {
    private const val PREFS_NAME = "alarm_wake"
    private const val KEY_RAMP_SECONDS = "ramp_seconds"
    private const val KEY_BOOST = "boost"
    private const val KEY_VOLUME_BEFORE_BOOST = "volume_before_boost"
    const val DEFAULT_RAMP_SECONDS = 120
    const val MAX_RAMP_SECONDS = 600

    fun save(context: Context, rampSeconds: Int, boost: Boolean) {
        preferences(context).edit()
            .putInt(KEY_RAMP_SECONDS, rampSeconds.coerceIn(0, MAX_RAMP_SECONDS))
            .putBoolean(KEY_BOOST, boost)
            .apply()
    }

    /** The configured rise, or a short one for a snoozed ring. */
    fun ramp(context: Context, snoozed: Boolean = false): AlarmVolumeRamp {
        val prefs = preferences(context)
        val ramp = AlarmVolumeRamp(
            prefs.getInt(KEY_RAMP_SECONDS, DEFAULT_RAMP_SECONDS)
                .coerceIn(0, MAX_RAMP_SECONDS) * 1_000L,
            prefs.getBoolean(KEY_BOOST, true),
        )
        return if (snoozed) ramp.forSnooze() else ramp
    }

    /** Raises the alarm stream to its maximum, remembering the first original volume. */
    @Synchronized
    fun boost(context: Context) {
        try {
            val audio = context.getSystemService(AudioManager::class.java) ?: return
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            val current = audio.getStreamVolume(AudioManager.STREAM_ALARM)
            if (current >= max) return
            val prefs = preferences(context)
            if (!prefs.contains(KEY_VOLUME_BEFORE_BOOST)) {
                prefs.edit().putInt(KEY_VOLUME_BEFORE_BOOST, current).commit()
            }
            audio.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
        } catch (_: Throwable) {
            // Some devices refuse volume changes (policy, Do Not Disturb):
            // the alarm keeps ringing at the user's own volume.
        }
    }

    /** Puts back the alarm volume saved by [boost], if any. */
    @Synchronized
    fun restoreVolume(context: Context) {
        val prefs = preferences(context)
        if (!prefs.contains(KEY_VOLUME_BEFORE_BOOST)) return
        val original = prefs.getInt(KEY_VOLUME_BEFORE_BOOST, -1)
        try {
            val audio = context.getSystemService(AudioManager::class.java)
            if (audio != null && original >= 0) {
                audio.setStreamVolume(AudioManager.STREAM_ALARM, original, 0)
            }
        } catch (_: Throwable) {
            // Nothing else to do; the saved value is dropped either way.
        }
        prefs.edit().remove(KEY_VOLUME_BEFORE_BOOST).commit()
    }

    private fun preferences(context: Context) =
        context.createDeviceProtectedStorageContext()
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
