package com.workoutnotes.workout_notes.sleep

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.workoutnotes.workout_notes.R
import com.workoutnotes.workout_notes.common.AlarmRinger
import com.workoutnotes.workout_notes.common.NotificationChannels
import com.workoutnotes.workout_notes.common.NotificationChannels.silent
import com.workoutnotes.workout_notes.common.PendingIntentFlags

class TraditionalAlarmRingingService : Service() {
    companion object {
        const val ACTION_START = "traditional_alarm.start"
        const val ACTION_DISMISS = "traditional_alarm.dismiss"
        const val ACTION_SNOOZE = "traditional_alarm.snooze"
        const val ACTION_MISSION_COMPLETE = "traditional_alarm.mission_complete"
        private const val CHANNEL_ID = "traditional_alarm"
        private const val NOTIFICATION_ID = 1210
        private const val REQUEST_OPEN = 1211
        private const val REQUEST_SNOOZE = 1212
        private const val REQUEST_DISMISS = 1213

        fun start(context: Context, id: String) = action(context, ACTION_START, id)
        fun dismiss(context: Context, id: String) = action(context, ACTION_DISMISS, id)
        fun snooze(context: Context, id: String) = action(context, ACTION_SNOOZE, id)
        fun missionComplete(context: Context, id: String) =
            action(context, ACTION_MISSION_COMPLETE, id)

        private fun action(context: Context, action: String, id: String) {
            val intent = Intent(context, TraditionalAlarmRingingService::class.java).apply {
                this.action = action
                putExtra(TraditionalAlarmScheduler.EXTRA_ID, id)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private val ringer by lazy { AlarmRinger(this) }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra(TraditionalAlarmScheduler.EXTRA_ID) ?: return START_NOT_STICKY
        val snapshot = TraditionalAlarmScheduler.read(this, id) ?: return START_NOT_STICKY
        when (intent.action) {
            ACTION_DISMISS -> {
                if (TraditionalAlarmStatePolicy.canFinishRinging(
                        snapshot.state,
                        snapshot.requiresMission,
                        missionCompleted = false,
                    )
                ) finish(id)
                return START_NOT_STICKY
            }
            ACTION_SNOOZE -> {
                if (snapshot.state == "ringing" &&
                    snapshot.snoozeEnabled &&
                    snapshot.snoozeCount < snapshot.maxSnoozes
                ) {
                    val snoozed = try {
                        TraditionalAlarmScheduler.snooze(this, id)
                    } catch (_: Throwable) {
                        null
                    }
                    if (snoozed != null) {
                        finishRinging()
                        stopSelf()
                    }
                }
                return START_NOT_STICKY
            }
            ACTION_MISSION_COMPLETE -> {
                if (TraditionalAlarmStatePolicy.canFinishRinging(
                        snapshot.state,
                        snapshot.requiresMission,
                        missionCompleted = true,
                    )
                ) finish(id)
                return START_NOT_STICKY
            }
        }
        if (snapshot.state != "ringing") return START_NOT_STICKY
        ensureChannel()
        startForeground(NOTIFICATION_ID, notification(snapshot))
        if (!ringer.hasPlayer) ringer.start()
        return START_STICKY
    }

    override fun onDestroy() {
        finishRinging()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun finish(id: String) {
        TraditionalAlarmScheduler.dismiss(this, id)
        finishRinging()
        stopSelf()
    }

    private fun ensureChannel() {
        NotificationChannels.ensure(
            this,
            CHANNEL_ID,
            getString(R.string.traditional_alarm_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ) {
            description = getString(R.string.traditional_alarm_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            silent()
        }
    }

    private fun serviceIntent(action: String, id: String) =
        Intent(this, TraditionalAlarmRingingService::class.java).apply {
            this.action = action
            putExtra(TraditionalAlarmScheduler.EXTRA_ID, id)
        }

    private fun notification(snapshot: TraditionalAlarmScheduler.Snapshot): Notification {
        val openIntent = Intent(this, TraditionalAlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(TraditionalAlarmScheduler.EXTRA_ID, snapshot.id)
        }
        val open = PendingIntent.getActivity(
            this,
            REQUEST_OPEN,
            openIntent,
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
        val body = getString(
            if (snapshot.requiresMission) {
                R.string.traditional_alarm_mission_body
            } else {
                R.string.traditional_alarm_wake_title
            },
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setColor(Color.rgb(91, 82, 171))
            .setContentTitle(getString(R.string.traditional_alarm_notification_title))
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
        if (snapshot.snoozeEnabled && snapshot.snoozeCount < snapshot.maxSnoozes) {
            val snooze = PendingIntent.getService(
                this,
                REQUEST_SNOOZE,
                serviceIntent(ACTION_SNOOZE, snapshot.id),
                PendingIntentFlags.UPDATE_IMMUTABLE,
            )
            builder.addAction(
                android.R.drawable.ic_lock_idle_alarm,
                getString(R.string.traditional_alarm_snooze),
                snooze,
            )
        }
        if (snapshot.requiresMission) {
            builder.addAction(
                android.R.drawable.ic_menu_camera,
                getString(R.string.traditional_alarm_open_mission),
                open,
            )
        } else {
            val dismiss = PendingIntent.getService(
                this,
                REQUEST_DISMISS,
                serviceIntent(ACTION_DISMISS, snapshot.id),
                PendingIntentFlags.UPDATE_IMMUTABLE,
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.traditional_alarm_dismiss),
                dismiss,
            )
        }
        return builder.build()
    }

    private fun finishRinging() {
        ringer.stop()
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
}
