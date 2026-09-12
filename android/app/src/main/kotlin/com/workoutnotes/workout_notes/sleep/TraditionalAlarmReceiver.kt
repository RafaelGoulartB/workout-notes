package com.workoutnotes.workout_notes.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TraditionalAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != TraditionalAlarmScheduler.ACTION_FIRE) return
        val id = intent.getStringExtra(TraditionalAlarmScheduler.EXTRA_ID) ?: return
        val alarmAt = intent.getLongExtra(TraditionalAlarmScheduler.EXTRA_ALARM_AT, Long.MIN_VALUE)
        if (!TraditionalAlarmScheduler.markRinging(context, id, alarmAt)) return
        TraditionalAlarmRingingService.start(context, id)
    }
}
