package com.workoutnotes.workout_notes.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TraditionalAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != TraditionalAlarmScheduler.ACTION_FIRE) return
        val id = intent.getStringExtra(TraditionalAlarmScheduler.EXTRA_ID) ?: return
        TraditionalAlarmScheduler.markRinging(context, id)
        TraditionalAlarmRingingService.start(context, id)
    }
}
