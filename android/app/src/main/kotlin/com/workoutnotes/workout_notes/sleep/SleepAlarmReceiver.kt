package com.workoutnotes.workout_notes.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SleepAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == SleepAlarmScheduler.ACTION_DISMISS_SNOOZE) {
            // "Turn off" on the snooze notification of an alarm without mission.
            if (SleepAlarmScheduler.dismissSnooze(context) != null) {
                SleepMonitoringService.alarmDismissed(context, SleepMonitorSessionDismiss.BUTTON)
            }
            return
        }
        if (intent?.action != SleepAlarmScheduler.ACTION_FIRE) return
        val alarmAt = intent.getLongExtra(
            SleepAlarmScheduler.EXTRA_ALARM_AT,
            System.currentTimeMillis(),
        )
        SleepAlarmScheduler.ring(context, alarmAt, SmartWakePolicy.TRIGGER_DEADLINE)
    }
}
