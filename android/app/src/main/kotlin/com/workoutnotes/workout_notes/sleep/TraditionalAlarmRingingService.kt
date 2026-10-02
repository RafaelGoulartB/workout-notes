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
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.workoutnotes.workout_notes.R
import com.workoutnotes.workout_notes.common.AlarmRinger
import com.workoutnotes.workout_notes.common.AlarmVolumeRamp
import com.workoutnotes.workout_notes.common.AlarmWakePrefs
import com.workoutnotes.workout_notes.common.NotificationChannels
import com.workoutnotes.workout_notes.common.NotificationChannels.silent
import com.workoutnotes.workout_notes.common.PendingIntentFlags

class TraditionalAlarmRingingService : Service() {
    companion object {
        const val ACTION_START = "traditional_alarm.start"
        const val ACTION_DISMISS = "traditional_alarm.dismiss"
        const val ACTION_SNOOZE = "traditional_alarm.snooze"
        const val ACTION_MISSION_COMPLETE = "traditional_alarm.mission_complete"

        /** Broadcast inside the app when a ring ends, so its screen can close. */
        const val ACTION_RING_ENDED = "traditional_alarm.ring_ended"
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
            // Only a ring owes startForeground(); dismiss, snooze and mission
            // answers may find the service already stopped and then return
            // without ever going foreground, which would crash the app.
            if (action == ACTION_START && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private val ringer by lazy { AlarmRinger(this) }
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var ringingId: String? = null
    private var timeout: Runnable? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val id = intent?.getStringExtra(TraditionalAlarmScheduler.EXTRA_ID)
        val snapshot = id?.let { TraditionalAlarmScheduler.read(this, it) }
        if (id == null || snapshot == null) {
            return if (action == ACTION_START) abandonStart() else idle()
        }
        when (action) {
            ACTION_DISMISS -> {
                if (TraditionalAlarmStatePolicy.canFinishRinging(
                        snapshot.state,
                        snapshot.requiresMission,
                        missionCompleted = false,
                    )
                ) {
                    finish(id)
                    return START_NOT_STICKY
                }
                return idle()
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
                        return START_NOT_STICKY
                    }
                }
                return idle()
            }
            ACTION_MISSION_COMPLETE -> {
                if (TraditionalAlarmStatePolicy.canFinishRinging(
                        snapshot.state,
                        snapshot.requiresMission,
                        missionCompleted = true,
                    )
                ) {
                    finish(id)
                    return START_NOT_STICKY
                }
                return idle()
            }
        }
        if (snapshot.state != "ringing") {
            return if (action == ACTION_START) abandonStart() else idle()
        }
        ensureChannel()
        try {
            startForeground(NOTIFICATION_ID, notification(snapshot))
        } catch (error: Throwable) {
            // Refused (e.g. right after a boot): ring again shortly instead
            // of crashing the app with the alarm stuck as "ringing".
            Log.w("TraditionalAlarm", "Ringing refused to start", error)
            TraditionalAlarmScheduler.recoverRefusedRing(this, id)
            stopSelf()
            return START_NOT_STICKY
        }
        armTimeout(id)
        if (!ringer.hasPlayer) {
            ringer.start(
                if (snapshot.gradualVolume) {
                    AlarmWakePrefs.ramp(this, snoozed = snapshot.snoozeCount > 0)
                } else {
                    AlarmVolumeRamp.NONE
                },
            )
        }
        return START_STICKY
    }

    override fun onDestroy() {
        finishRinging()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** Nothing to do for this command: keep ringing if something does, else stop. */
    private fun idle(): Int {
        if (ringingId == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    /**
     * A start that arrived through startForegroundService() but has nothing to
     * ring (the alarm was dismissed or deleted meanwhile). The foreground
     * contract still has to be honoured before stopping, and a ring that is
     * already going on must not be cut.
     */
    private fun abandonStart(): Int {
        ensureChannel()
        val current = ringingId?.let { TraditionalAlarmScheduler.read(this, it) }
        try {
            startForeground(
                NOTIFICATION_ID,
                if (current != null) notification(current) else placeholder(),
            )
        } catch (error: Throwable) {
            Log.w("TraditionalAlarm", "Could not enter the foreground", error)
        }
        if (current != null) return START_STICKY
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        return START_NOT_STICKY
    }

    private fun finish(id: String) {
        try {
            TraditionalAlarmScheduler.dismiss(this, id)
        } catch (error: Throwable) {
            // E.g. exact alarms revoked while rescheduling a repeating alarm:
            // the alarm still has to stop ringing.
            Log.w("TraditionalAlarm", "Could not close alarm $id", error)
        }
        finishRinging()
        stopSelf()
    }

    /**
     * Like the stock clock, a ring nobody answers does not go on forever: it
     * snoozes when the alarm can still snooze, otherwise it ends and leaves a
     * "missed alarm" notification.
     */
    private fun armTimeout(id: String) {
        if (ringingId == id && timeout != null) return
        cancelTimeout()
        ringingId = id
        acquireWakeLock()
        val callback = Runnable { onRingTimeout(id) }
        timeout = callback
        handler.postDelayed(callback, TraditionalAlarmTimeoutPolicy.RING_TIMEOUT_MILLIS)
    }

    private fun cancelTimeout() {
        timeout?.let(handler::removeCallbacks)
        timeout = null
    }

    private fun onRingTimeout(id: String) {
        timeout = null
        val snapshot = TraditionalAlarmScheduler.read(this, id)
        var action = if (snapshot == null) {
            TraditionalAlarmTimeoutPolicy.Action.NONE
        } else {
            TraditionalAlarmTimeoutPolicy.actionOnTimeout(
                snapshot.state,
                snapshot.snoozeEnabled,
                snapshot.snoozeCount,
                snapshot.maxSnoozes,
                snapshot.requiresMission,
            )
        }
        if (action == TraditionalAlarmTimeoutPolicy.Action.KEEP_RINGING) return
        if (snapshot != null && action == TraditionalAlarmTimeoutPolicy.Action.SNOOZE) {
            val snoozed = try {
                TraditionalAlarmScheduler.snooze(this, id)
            } catch (_: Throwable) {
                null
            }
            if (snoozed != null) {
                finishRinging()
                stopSelf()
                return
            }
            action = TraditionalAlarmTimeoutPolicy.Action.MISSED
        }
        if (snapshot != null && action == TraditionalAlarmTimeoutPolicy.Action.MISSED) {
            TraditionalAlarmMissedNotification.show(this, snapshot)
            finish(id)
            return
        }
        // Nothing is ringing any more for this alarm.
        finishRinging()
        stopSelf()
    }

    private fun acquireWakeLock() {
        // Keeps the timeout timer running while the screen is off.
        val lock = wakeLock ?: (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "WorkoutNotes:TraditionalAlarm")
            .apply { setReferenceCounted(false) }
            .also { wakeLock = it }
        lock.acquire(TraditionalAlarmTimeoutPolicy.RING_TIMEOUT_MILLIS + 60_000L)
    }

    private fun placeholder(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(getString(R.string.traditional_alarm_notification_title))
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()

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
        cancelTimeout()
        ringer.stop()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        ringingId?.let { ended ->
            ringingId = null
            // Lets an open alarm screen close itself.
            sendBroadcast(
                Intent(ACTION_RING_ENDED)
                    .setPackage(packageName)
                    .putExtra(TraditionalAlarmScheduler.EXTRA_ID, ended),
            )
        }
    }
}
