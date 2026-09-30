package com.workoutnotes.workout_notes.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.workoutnotes.workout_notes.common.AlarmWakePrefs
import com.workoutnotes.workout_notes.medication.MedicationReminderScheduler

class SleepAlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (
            intent?.action == Intent.ACTION_BOOT_COMPLETED ||
            intent?.action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            intent?.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            // A boost left behind by a ring that never stopped cleanly.
            AlarmWakePrefs.restoreVolume(context)
            SleepAlarmScheduler.restore(context)
            TraditionalAlarmScheduler.restore(context)
            MedicationReminderScheduler.restore(context)
        }
    }
}
