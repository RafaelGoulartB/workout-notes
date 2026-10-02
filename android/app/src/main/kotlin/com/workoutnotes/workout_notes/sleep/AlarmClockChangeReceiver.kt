package com.workoutnotes.workout_notes.sleep

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.workoutnotes.workout_notes.medication.MedicationReminderScheduler

/**
 * Re-arms the alarms when the time zone or the clock changes, and when the
 * exact-alarm permission is granted or revoked.
 *
 * Alarms are armed for an absolute instant, so after travel a 07:00 alarm
 * would still ring at the old zone's 07:00. Alarms defined by a local hour
 * and minute (standalone alarms, medication reminders) get their instant
 * derived from that definition again. Like the boot receiver, each scheduler
 * runs on its own so one failing leaves the others armed; unlike it, nothing
 * is rung or started here (a ringing alarm keeps its service, and a due
 * alarm is fired by the system or restored on the next launch).
 */
class AlarmClockChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val refreshLocalTimes = when (intent?.action) {
            Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED -> true
            // Granted again: the alarms the system dropped are armed again.
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> false
            else -> return
        }
        val steps = listOf<Pair<String, () -> Unit>>(
            "sleep" to { SleepAlarmScheduler.rearmPending(context) },
            "traditional" to { TraditionalAlarmScheduler.rearmPending(context, refreshLocalTimes) },
            "medication" to { MedicationReminderScheduler.rearmPending(context, refreshLocalTimes) },
        )
        for ((name, step) in steps) {
            try {
                step()
            } catch (error: Throwable) {
                Log.w("AlarmClockChange", "Re-arming $name alarms failed", error)
            }
        }
    }
}
