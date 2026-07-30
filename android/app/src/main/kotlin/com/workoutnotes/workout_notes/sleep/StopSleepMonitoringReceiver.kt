package com.workoutnotes.workout_notes.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StopSleepMonitoringReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != SleepMonitorNotification.ACTION_STOP) return
        context.startService(
            Intent(context, SleepMonitoringService::class.java).apply {
                action = SleepMonitorNotification.ACTION_STOP
            },
        )
    }
}
