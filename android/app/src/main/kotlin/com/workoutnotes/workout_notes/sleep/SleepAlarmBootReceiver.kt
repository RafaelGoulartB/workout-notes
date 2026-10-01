package com.workoutnotes.workout_notes.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.workoutnotes.workout_notes.common.AlarmWakePrefs
import com.workoutnotes.workout_notes.medication.MedicationReminderScheduler

class SleepAlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (
            intent?.action == Intent.ACTION_BOOT_COMPLETED ||
            intent?.action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            intent?.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            // Each step on its own: one failing must not leave the others
            // unscheduled. A boost left behind by a ring that never stopped
            // cleanly is undone first.
            val steps = listOf<Pair<String, () -> Unit>>(
                "volume" to { AlarmWakePrefs.restoreVolume(context) },
                "sleep" to { SleepAlarmScheduler.restore(context) },
                "traditional" to { TraditionalAlarmScheduler.restore(context, fromBoot = true) },
                "medication" to { MedicationReminderScheduler.restore(context, fromBoot = true) },
            )
            for ((name, step) in steps) {
                try {
                    step()
                } catch (error: Throwable) {
                    Log.w("SleepAlarmBoot", "Restoring $name alarms failed", error)
                }
            }
        }
    }
}
