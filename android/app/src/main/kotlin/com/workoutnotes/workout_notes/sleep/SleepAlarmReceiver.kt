package com.workoutnotes.workout_notes.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class SleepAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != SleepAlarmScheduler.ACTION_FIRE) return
        val alarmAt = intent.getLongExtra(
            SleepAlarmScheduler.EXTRA_ALARM_AT,
            System.currentTimeMillis(),
        )
        SleepAlarmScheduler.markFired(context)
        SleepMonitoringService.stopCurrent("alarm")

        val ringing = Intent(context, SleepAlarmRingingService::class.java).apply {
            action = SleepAlarmRingingService.ACTION_START
            putExtra(SleepAlarmScheduler.EXTRA_ALARM_AT, alarmAt)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(ringing)
        } else {
            context.startService(ringing)
        }
    }
}
