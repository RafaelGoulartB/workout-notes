package com.workoutnotes.workout_notes.medication

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.workoutnotes.workout_notes.R
import com.workoutnotes.workout_notes.common.AlarmRinger

/**
 * Rings (sound + vibration) for a medication dose that was not confirmed in
 * time, with a full-screen confirmation screen. It stops only when the dose is
 * confirmed or skipped.
 */
class MedicationAlarmService : Service() {
    companion object {
        private const val ACTION_START = "medication_alarm.start"
        private const val ACTION_STOP = "medication_alarm.stop"
        private const val NOTIFICATION_ID = 1310

        fun start(context: Context, id: String) = send(context, ACTION_START, id)

        fun stop(context: Context, id: String) {
            // Stopping never needs a foreground start.
            context.startService(
                Intent(context, MedicationAlarmService::class.java).apply {
                    action = ACTION_STOP
                    putExtra(MedicationReminderScheduler.EXTRA_SLOT_ID, id)
                },
            )
        }

        private fun send(context: Context, action: String, id: String) {
            val intent = Intent(context, MedicationAlarmService::class.java).apply {
                this.action = action
                putExtra(MedicationReminderScheduler.EXTRA_SLOT_ID, id)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private val ringer by lazy { AlarmRinger(this) }
    private var ringingSlotId: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra(MedicationReminderScheduler.EXTRA_SLOT_ID)
        if (intent?.action == ACTION_STOP) {
            if (id == null || id == ringingSlotId || ringingSlotId == null) {
                stopRinging()
                stopSelf()
            }
            return START_NOT_STICKY
        }
        val slot = id?.let { MedicationReminderScheduler.read(this, it) }
        MedicationNotifications.ensureChannels(this)
        if (slot == null || slot.state != MedicationReminderPolicy.STATE_RINGING) {
            // A foreground start must always call startForeground once.
            startForeground(NOTIFICATION_ID, placeholder())
            stopRinging()
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            startForeground(NOTIFICATION_ID, notification(slot))
        } catch (error: Throwable) {
            // Refused (e.g. right after a boot): escalate again shortly
            // instead of crashing the app.
            Log.w("MedicationAlarm", "Alarm refused to start", error)
            MedicationReminderScheduler.recoverRefusedRing(this, slot.id)
            stopSelf()
            return START_NOT_STICKY
        }
        ringingSlotId = slot.id
        if (!ringer.hasPlayer) ringer.start()
        return START_STICKY
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun notification(slot: MedicationReminderScheduler.Slot): Notification {
        val open = MedicationNotifications.confirmIntent(this, slot, slot.pendingDoseKey)
        return NotificationCompat.Builder(this, MedicationNotifications.ALARM_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setColor(MedicationNotifications.ACCENT)
            .setContentTitle(getString(R.string.medication_alarm_title))
            .setContentText(MedicationNotifications.doseLabel(slot))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .addAction(
                android.R.drawable.ic_menu_agenda,
                getString(R.string.medication_open_confirmation),
                open,
            )
            .build()
    }

    private fun placeholder(): Notification =
        NotificationCompat.Builder(this, MedicationNotifications.ALARM_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(getString(R.string.medication_alarm_title))
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()

    private fun stopRinging() {
        ringer.stop()
        ringingSlotId = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
}
