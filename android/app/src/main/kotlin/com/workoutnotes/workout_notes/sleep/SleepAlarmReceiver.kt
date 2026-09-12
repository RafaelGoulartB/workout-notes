package com.workoutnotes.workout_notes.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class SleepAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != SleepAlarmScheduler.ACTION_FIRE) return
        val snapshot = SleepAlarmScheduler.read(context)
        val alarmAt = intent.getLongExtra(
            SleepAlarmScheduler.EXTRA_ALARM_AT,
            System.currentTimeMillis(),
        )
        if (!SleepAlarmScheduler.markFired(context, alarmAt)) return
        SleepMonitoringService.stopCurrent("alarm")

        val ringing = Intent(context, SleepAlarmRingingService::class.java).apply {
            action = SleepAlarmRingingService.ACTION_START
            putExtra(SleepAlarmScheduler.EXTRA_ALARM_AT, alarmAt)
            putExtra(SleepAlarmScheduler.EXTRA_SESSION_ID, snapshot?.sessionId)
            putExtra(SleepAlarmScheduler.EXTRA_MONITOR_MODE, snapshot?.monitorMode)
            putExtra(SleepAlarmScheduler.EXTRA_MISSION_TYPE, snapshot?.missionType)
            putExtra(SleepAlarmScheduler.EXTRA_MISSION_HASH, snapshot?.missionHash)
            putExtra(SleepAlarmScheduler.EXTRA_MISSION_SALT, snapshot?.missionSalt)
            putExtra(SleepAlarmScheduler.EXTRA_MISSION_FORMAT, snapshot?.missionFormat)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(ringing)
        } else {
            context.startService(ringing)
        }
    }
}
