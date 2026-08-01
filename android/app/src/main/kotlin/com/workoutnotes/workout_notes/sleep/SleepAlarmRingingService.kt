package com.workoutnotes.workout_notes.sleep

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.workoutnotes.workout_notes.R

class SleepAlarmRingingService : Service() {
    companion object {
        const val ACTION_START = "com.workoutnotes.workout_notes.sleep.ALARM_START"
        const val ACTION_DISMISS = "com.workoutnotes.workout_notes.sleep.ALARM_DISMISS"
        const val ACTION_PAUSE_FOR_EMERGENCY = "com.workoutnotes.workout_notes.sleep.ALARM_PAUSE_FOR_EMERGENCY"
        const val ACTION_RESUME_AFTER_EMERGENCY = "com.workoutnotes.workout_notes.sleep.ALARM_RESUME_AFTER_EMERGENCY"
        private const val ACTION_COMPLETE = "com.workoutnotes.workout_notes.sleep.ALARM_COMPLETE"
        private const val EXTRA_METHOD = "dismiss_method"
        const val CHANNEL_ID = "sleep_alarm"
        const val NOTIFICATION_ID = 1203

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

        fun pauseForEmergency(context: Context) {
            sendAction(context, ACTION_PAUSE_FOR_EMERGENCY)
        }

        fun resumeAfterEmergency(context: Context) {
            sendAction(context, ACTION_RESUME_AFTER_EMERGENCY)
        }

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
            if (snapshot.state != SleepAlarmScheduler.STATE_RINGING ||
                !snapshot.requiresMission || snapshot.missionHash == null ||
                snapshot.missionSalt == null
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
            if (snapshot.state != SleepAlarmScheduler.STATE_RINGING ||
                !snapshot.requiresMission ||
                !SleepAlarmScheduler.isEmergencyChallengeActive(context)
            ) return 0
            if (SleepAlarmScheduler.emergencyTaps(context) >= SleepAlarmScheduler.MAX_EMERGENCY_TAPS) {
                return SleepAlarmScheduler.MAX_EMERGENCY_TAPS
            }
            val taps = SleepAlarmScheduler.incrementEmergencyTaps(context)
            SleepMonitoringService.publishAlarmRinging(context)
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

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var emergencyResume: Runnable? = null
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
        if (action == ACTION_DISMISS) {
            if (snapshot?.state != SleepAlarmScheduler.STATE_RINGING) {
                return START_NOT_STICKY
            }
            if (snapshot.requiresMission) return START_STICKY
            finishAlarm(SleepMonitorSessionDismiss.BUTTON)
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_COMPLETE) {
            val method = intent.getStringExtra(EXTRA_METHOD)
            if (snapshot?.state == SleepAlarmScheduler.STATE_RINGING &&
                snapshot.requiresMission &&
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
        } else if (ringingPaused) {
            SleepAlarmScheduler.resetEmergencyChallenge(this)
            acquireWakeLock()
            resumeRinging()
        } else if (player == null) {
            acquireWakeLock()
            startSound()
            startVibration()
        }
        SleepMonitoringService.publishAlarmRinging(this)
        return START_STICKY
    }

    override fun onDestroy() {
        emergencyResume?.let(handler::removeCallbacks)
        stopRinging()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun finishAlarm(method: String) {
        emergencyResume?.let(handler::removeCallbacks)
        emergencyResume = null
        SleepMonitoringService.alarmDismissed(this, method)
        SleepAlarmScheduler.complete(this)
        stopRinging()
        stopSelf()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.sleep_alarm_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = getString(R.string.sleep_alarm_channel_description)
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
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
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
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
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
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
        return builder.build()
    }

    private fun startSound() {
        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(this@SleepAlarmRingingService, alarmUri)
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Throwable) {
            player?.release()
            player = null
        }
    }

    @Suppress("DEPRECATION")
    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 700, 300, 700, 1200)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun pauseRinging() {
        ringingPaused = true
        try {
            if (player?.isPlaying == true) player?.pause()
        } catch (_: Throwable) {
        }
        vibrator?.cancel()
    }

    private fun resumeRinging() {
        ringingPaused = false
        if (player == null) {
            startSound()
        } else {
            try {
                if (player?.isPlaying != true) player?.start()
            } catch (_: Throwable) {
                player?.release()
                player = null
                startSound()
            }
        }
        startVibration()
        emergencyResume?.let(handler::removeCallbacks)
        emergencyResume = null
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

    private fun acquireWakeLock() {
        val manager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = manager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "WorkoutNotes:SleepAlarm",
        ).apply { acquire() }
    }

    private fun stopRinging() {
        ringingPaused = false
        emergencyResume?.let(handler::removeCallbacks)
        emergencyResume = null
        try { player?.stop() } catch (_: Throwable) {}
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
}

private object SleepMonitorSessionDismiss {
    const val BUTTON = "button"
    const val BARCODE = "barcode"
    const val EMERGENCY = "emergency_1000_taps"
}
