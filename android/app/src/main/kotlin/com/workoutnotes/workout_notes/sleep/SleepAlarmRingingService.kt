package com.workoutnotes.workout_notes.sleep

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.workoutnotes.workout_notes.R
import com.workoutnotes.workout_notes.common.AlarmRinger
import com.workoutnotes.workout_notes.common.AlarmWakePrefs
import com.workoutnotes.workout_notes.common.NotificationChannels
import com.workoutnotes.workout_notes.common.NotificationChannels.silent
import com.workoutnotes.workout_notes.common.PendingIntentFlags

class SleepAlarmRingingService : Service() {
    companion object {
        const val ACTION_START = "com.workoutnotes.workout_notes.sleep.ALARM_START"
        const val ACTION_DISMISS = "com.workoutnotes.workout_notes.sleep.ALARM_DISMISS"
        const val ACTION_SNOOZE = "com.workoutnotes.workout_notes.sleep.ALARM_SNOOZE"
        const val ACTION_PAUSE_FOR_EMERGENCY = "com.workoutnotes.workout_notes.sleep.ALARM_PAUSE_FOR_EMERGENCY"
        const val ACTION_RESUME_AFTER_EMERGENCY = "com.workoutnotes.workout_notes.sleep.ALARM_RESUME_AFTER_EMERGENCY"
        const val ACTION_PAUSE_FOR_BARCODE = "com.workoutnotes.workout_notes.sleep.ALARM_PAUSE_FOR_BARCODE"
        const val ACTION_RESUME_AFTER_BARCODE = "com.workoutnotes.workout_notes.sleep.ALARM_RESUME_AFTER_BARCODE"
        private const val ACTION_COMPLETE = "com.workoutnotes.workout_notes.sleep.ALARM_COMPLETE"
        private const val EXTRA_METHOD = "dismiss_method"
        const val CHANNEL_ID = "sleep_alarm"
        const val NOTIFICATION_ID = 1203
        private const val WAKE_LOCK_TIMEOUT_MS = 30L * 60L * 1000L

        fun start(context: Context, alarmAt: Long) {
            val intent = Intent(context, SleepAlarmRingingService::class.java).apply {
                action = ACTION_START
                putExtra(SleepAlarmScheduler.EXTRA_ALARM_AT, alarmAt)
                SleepAlarmScheduler.read(context)?.let { snapshot ->
                    putExtra(SleepAlarmScheduler.EXTRA_SESSION_ID, snapshot.sessionId)
                    putExtra(SleepAlarmScheduler.EXTRA_MONITOR_MODE, snapshot.monitorMode)
                    putExtra(SleepAlarmScheduler.EXTRA_MISSION_TYPE, snapshot.missionType)
                    putExtra(SleepAlarmScheduler.EXTRA_MISSION_HASH, snapshot.missionHash)
                    putExtra(SleepAlarmScheduler.EXTRA_MISSION_SALT, snapshot.missionSalt)
                    putExtra(SleepAlarmScheduler.EXTRA_MISSION_FORMAT, snapshot.missionFormat)
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }

        fun dismiss(context: Context) {
            context.startService(Intent(context, SleepAlarmRingingService::class.java).apply {
                action = ACTION_DISMISS
            })
        }

        fun snooze(context: Context) {
            sendAction(context, ACTION_SNOOZE)
        }

        // Pausing and resuming only apply to a ringing alarm. During a snooze
        // nothing rings, and starting the foreground service there would
        // break its startForeground() contract.
        fun pauseForEmergency(context: Context) {
            if (isRinging(context)) sendAction(context, ACTION_PAUSE_FOR_EMERGENCY)
        }

        fun resumeAfterEmergency(context: Context) {
            if (isRinging(context)) {
                sendAction(context, ACTION_RESUME_AFTER_EMERGENCY)
            } else {
                SleepAlarmScheduler.resetEmergencyChallenge(context)
            }
        }

        fun pauseForBarcode(context: Context) {
            if (isRinging(context)) sendAction(context, ACTION_PAUSE_FOR_BARCODE)
        }

        fun resumeAfterBarcode(context: Context) {
            if (isRinging(context)) {
                sendAction(context, ACTION_RESUME_AFTER_BARCODE)
            } else {
                SleepAlarmScheduler.resetBarcodeChallenge(context)
            }
        }

        private fun isRinging(context: Context): Boolean =
            SleepAlarmScheduler.read(context)?.state == SleepAlarmScheduler.STATE_RINGING

        private fun sendAction(context: Context, action: String) {
            val intent = Intent(context, SleepAlarmRingingService::class.java).apply {
                this.action = action
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }

        fun completeBarcode(context: Context, rawValue: String, format: String): Boolean {
            val snapshot = SleepAlarmScheduler.read(context) ?: return false
            if (!snapshot.canRunMission || snapshot.missionHash == null ||
                snapshot.missionSalt == null ||
                !SleepAlarmScheduler.isBarcodeChallengeActive(context)
            ) return false
            val actual = BarcodeMissionCrypto.hash(format, rawValue, snapshot.missionSalt)
            if (!BarcodeMissionCrypto.constantTimeEquals(actual, snapshot.missionHash)) {
                return false
            }
            complete(context, SleepMonitorSessionDismiss.BARCODE)
            return true
        }

        fun tapEmergency(context: Context): Int {
            val snapshot = SleepAlarmScheduler.read(context) ?: return 0
            if (!snapshot.canRunMission ||
                !SleepAlarmScheduler.isEmergencyChallengeActive(context)
            ) return 0
            if (SleepAlarmScheduler.emergencyTaps(context) >= SleepAlarmScheduler.MAX_EMERGENCY_TAPS) {
                return SleepAlarmScheduler.MAX_EMERGENCY_TAPS
            }
            val taps = SleepAlarmScheduler.incrementEmergencyTaps(context)
            if (snapshot.state == SleepAlarmScheduler.STATE_RINGING) {
                SleepMonitoringService.publishAlarmRinging(context)
            }
            if (taps >= SleepAlarmScheduler.MAX_EMERGENCY_TAPS) {
                complete(context, SleepMonitorSessionDismiss.EMERGENCY)
            }
            return taps.coerceAtMost(SleepAlarmScheduler.MAX_EMERGENCY_TAPS)
        }

        private fun complete(context: Context, method: String) {
            context.startService(Intent(context, SleepAlarmRingingService::class.java).apply {
                action = ACTION_COMPLETE
                putExtra(EXTRA_METHOD, method)
            })
        }
    }

    private val ringer by lazy { AlarmRinger(this) }
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var emergencyResume: Runnable? = null
    private var barcodeResume: Runnable? = null
    private var ringingPaused = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val snapshot = SleepAlarmScheduler.read(this)
        val action = intent?.action
        val alarmAt = snapshot?.alarmAtMillis ?: intent?.getLongExtra(
            SleepAlarmScheduler.EXTRA_ALARM_AT,
            System.currentTimeMillis(),
        ) ?: System.currentTimeMillis()
        if (action == ACTION_PAUSE_FOR_EMERGENCY) {
            if (snapshot?.state != SleepAlarmScheduler.STATE_RINGING ||
                snapshot.requiresMission != true
            ) return START_NOT_STICKY
            ensureChannel()
            startForeground(
                NOTIFICATION_ID,
                buildNotification(alarmAt, protected = true),
            )
            val remaining = SleepAlarmScheduler.emergencyRemainingMillis(this)
            acquireWakeLock()
            if (remaining <= 0L) {
                SleepAlarmScheduler.resetEmergencyChallenge(this)
                resumeRinging()
            } else {
                pauseRinging()
                scheduleEmergencyResume(remaining)
            }
            SleepMonitoringService.publishAlarmRinging(this)
            return START_STICKY
        }
        if (action == ACTION_RESUME_AFTER_EMERGENCY) {
            if (snapshot?.state != SleepAlarmScheduler.STATE_RINGING) {
                return START_NOT_STICKY
            }
            SleepAlarmScheduler.resetEmergencyChallenge(this)
            ensureChannel()
            startForeground(
                NOTIFICATION_ID,
                buildNotification(alarmAt, protected = snapshot.requiresMission),
            )
            acquireWakeLock()
            resumeRinging()
            SleepMonitoringService.publishAlarmRinging(this)
            return START_STICKY
        }
        if (action == ACTION_PAUSE_FOR_BARCODE) {
            if (snapshot?.state != SleepAlarmScheduler.STATE_RINGING ||
                snapshot.requiresMission != true ||
                !SleepAlarmScheduler.isBarcodePauseActive(this)
            ) return START_NOT_STICKY
            ensureChannel()
            startForeground(
                NOTIFICATION_ID,
                buildNotification(alarmAt, protected = true),
            )
            val remaining = SleepAlarmScheduler.barcodeRemainingMillis(this)
            acquireWakeLock()
            if (remaining <= 0L) {
                SleepAlarmScheduler.resetBarcodeChallenge(this)
                resumeRinging()
            } else {
                pauseRinging()
                scheduleBarcodeResume(remaining)
            }
            SleepMonitoringService.publishAlarmRinging(this)
            return START_STICKY
        }

        if (action == ACTION_RESUME_AFTER_BARCODE) {
            if (snapshot?.state != SleepAlarmScheduler.STATE_RINGING) {
                return START_NOT_STICKY
            }
            SleepAlarmScheduler.resetBarcodeChallenge(this)
            ensureChannel()
            startForeground(
                NOTIFICATION_ID,
                buildNotification(alarmAt, protected = snapshot.requiresMission),
            )
            acquireWakeLock()
            resumeRinging()
            SleepMonitoringService.publishAlarmRinging(this)
            return START_STICKY
        }

        if (action == ACTION_DISMISS) {
            if (snapshot?.state != SleepAlarmScheduler.STATE_RINGING) {
                return START_NOT_STICKY
            }
            if (snapshot.requiresMission) return START_STICKY
            finishAlarm(SleepMonitorSessionDismiss.BUTTON)
            return START_NOT_STICKY
        }
        if (action == ACTION_SNOOZE) {
            // Started with startForegroundService(): honour its contract
            // even though the notification is removed right after.
            try {
                ensureChannel()
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(alarmAt, snapshot?.requiresMission == true),
                )
            } catch (_: Throwable) {
                // Started with startService() from a notification action: no contract.
            }
            val snoozed = try {
                SleepAlarmScheduler.snooze(this)
            } catch (_: Throwable) {
                false
            }
            if (snoozed) {
                SleepMonitoringService.publishAlarmSnoozing(this)
                stopRinging()
                stopSelf()
            } else if (snapshot?.state != SleepAlarmScheduler.STATE_RINGING) {
                // A stale snooze action with nothing ringing.
                stopRinging()
                stopSelf()
            }
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_COMPLETE) {
            val method = intent.getStringExtra(EXTRA_METHOD)
            // Also completes early, during a snooze.
            if (snapshot?.canRunMission == true &&
                method in setOf(SleepMonitorSessionDismiss.BARCODE, SleepMonitorSessionDismiss.EMERGENCY)
            ) {
                finishAlarm(method!!)
                return START_NOT_STICKY
            }
            return START_STICKY
        }

        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification(alarmAt, snapshot?.requiresMission == true))
        val emergencyRemaining = SleepAlarmScheduler.emergencyRemainingMillis(this)
        if (emergencyRemaining > 0L) {
            acquireWakeLock()
            pauseRinging()
            scheduleEmergencyResume(emergencyRemaining)
        } else if (
            SleepAlarmScheduler.isBarcodePauseActive(this) &&
            SleepAlarmScheduler.barcodeRemainingMillis(this) > 0L
        ) {
            acquireWakeLock()
            pauseRinging()
            scheduleBarcodeResume(SleepAlarmScheduler.barcodeRemainingMillis(this))
        } else if (ringingPaused) {
            SleepAlarmScheduler.resetEmergencyChallenge(this)
            SleepAlarmScheduler.resetBarcodeChallenge(this)
            acquireWakeLock()
            resumeRinging()
        } else if (!ringer.hasPlayer) {
            acquireWakeLock()
            ringer.start(AlarmWakePrefs.ramp(this, snoozed = (snapshot?.snoozeCount ?: 0) > 0))
        }
        SleepMonitoringService.publishAlarmRinging(this)
        return START_STICKY
    }

    override fun onDestroy() {
        emergencyResume?.let(handler::removeCallbacks)
        barcodeResume?.let(handler::removeCallbacks)
        stopRinging()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun finishAlarm(method: String) {
        emergencyResume?.let(handler::removeCallbacks)
        barcodeResume?.let(handler::removeCallbacks)
        emergencyResume = null
        barcodeResume = null
        SleepMonitoringService.alarmDismissed(this, method)
        SleepAlarmScheduler.complete(this)
        stopRinging()
        stopSelf()
    }

    private fun ensureChannel() {
        NotificationChannels.ensure(
            this,
            CHANNEL_ID,
            getString(R.string.sleep_alarm_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ) {
            description = getString(R.string.sleep_alarm_channel_description)
            silent()
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
    }

    private fun buildNotification(alarmAt: Long, protected: Boolean): Notification {
        val targetActivity = if (
            protected && SleepAlarmScheduler.isEmergencyChallengeActive(this)
        ) {
            SleepEmergencyChallengeActivity::class.java
        } else {
            SleepAlarmActivity::class.java
        }
        val activityIntent = PendingIntent.getActivity(
            this,
            1204,
            Intent(this, targetActivity).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(SleepAlarmScheduler.EXTRA_ALARM_AT, alarmAt)
            },
            PendingIntentFlags.UPDATE_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setColor(Color.rgb(91, 82, 171))
            .setContentTitle(getString(R.string.sleep_alarm_notification_title))
            .setContentText(
                if (protected) getString(R.string.sleep_alarm_mission_notification_body)
                else getString(R.string.sleep_alarm_notification_body),
            )
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(activityIntent)
            .setFullScreenIntent(activityIntent, true)
        if (!protected) {
            val dismissIntent = PendingIntent.getService(
                this,
                1205,
                Intent(this, SleepAlarmRingingService::class.java).apply {
                    action = ACTION_DISMISS
                },
                PendingIntentFlags.UPDATE_IMMUTABLE,
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.sleep_alarm_dismiss),
                dismissIntent,
            )
        } else {
            builder.addAction(
                android.R.drawable.ic_menu_camera,
                getString(R.string.sleep_alarm_open_mission),
                activityIntent,
            )
        }
        if (SleepAlarmScheduler.canSnooze(this)) {
            val snoozeIntent = PendingIntent.getService(
                this,
                1206,
                Intent(this, SleepAlarmRingingService::class.java).apply {
                    action = ACTION_SNOOZE
                },
                PendingIntentFlags.UPDATE_IMMUTABLE,
            )
            builder.addAction(
                android.R.drawable.ic_lock_idle_alarm,
                getString(R.string.sleep_alarm_snooze),
                snoozeIntent,
            )
        }
        return builder.build()
    }

    private fun pauseRinging() {
        ringingPaused = true
        ringer.pause()
    }

    private fun resumeRinging() {
        ringingPaused = false
        ringer.resume()
        emergencyResume?.let(handler::removeCallbacks)
        barcodeResume?.let(handler::removeCallbacks)
        emergencyResume = null
        barcodeResume = null
    }

    private fun scheduleEmergencyResume(remainingMillis: Long) {
        emergencyResume?.let(handler::removeCallbacks)
        val callback = Runnable {
            if (SleepAlarmScheduler.isEmergencyChallengeActive(this)) {
                scheduleEmergencyResume(SleepAlarmScheduler.emergencyRemainingMillis(this))
                return@Runnable
            }
            if (SleepAlarmScheduler.read(this)?.state == SleepAlarmScheduler.STATE_RINGING) {
                SleepAlarmScheduler.resetEmergencyChallenge(this)
                resumeRinging()
                SleepMonitoringService.publishAlarmRinging(this)
            }
        }
        emergencyResume = callback
        handler.postDelayed(callback, remainingMillis.coerceAtLeast(1L))
    }

    private fun scheduleBarcodeResume(remainingMillis: Long) {
        barcodeResume?.let(handler::removeCallbacks)
        val callback = Runnable {
            if (SleepAlarmScheduler.isBarcodeChallengeActive(this)) {
                scheduleBarcodeResume(SleepAlarmScheduler.barcodeRemainingMillis(this))
                return@Runnable
            }
            if (SleepAlarmScheduler.read(this)?.state == SleepAlarmScheduler.STATE_RINGING) {
                SleepAlarmScheduler.resetBarcodeChallenge(this)
                resumeRinging()
                SleepMonitoringService.publishAlarmRinging(this)
            }
        }
        barcodeResume = callback
        handler.postDelayed(callback, remainingMillis.coerceAtLeast(1L))
    }

    private fun acquireWakeLock() {
        // One non-counted lock, re-armed on every call: repeated acquisitions
        // extend the timeout instead of leaking extra locks.
        val lock = wakeLock ?: (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "WorkoutNotes:SleepAlarm")
            .apply { setReferenceCounted(false) }
            .also { wakeLock = it }
        lock.acquire(WAKE_LOCK_TIMEOUT_MS)
    }

    private fun stopRinging() {
        ringingPaused = false
        emergencyResume?.let(handler::removeCallbacks)
        barcodeResume?.let(handler::removeCallbacks)
        emergencyResume = null
        barcodeResume = null
        ringer.stop()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
}

internal object SleepMonitorSessionDismiss {
    const val BUTTON = "button"
    const val BARCODE = "barcode"
    const val EMERGENCY = "emergency_500_taps"
}
