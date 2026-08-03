package com.workoutnotes.workout_notes.sleep

import android.Manifest
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.content.ContextCompat
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.roundToInt

class SleepMonitoringService : Service() {
    companion object {
        private const val MAX_SESSION_MILLIS = 16L * 60L * 60L * 1_000L
        private var activeInstance: SleepMonitoringService? = null
        @Volatile private var lastState: Map<String, Any?>? = null
        @Volatile var eventSink: ((Map<String, Any?>) -> Unit)? = null

        fun startResponse(
            context: android.content.Context,
            sessionId: String,
            alarmAtMillis: Long,
            monitorMode: String,
        ): Map<String, Any?> {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
            return state(
                context,
                status = "starting",
                microphoneGranted = granted,
            ) + mapOf(
                "session_id" to sessionId,
                "monitor_mode" to monitorMode,
                "alarm_at" to if (alarmAtMillis > 0L) {
                    Instant.ofEpochMilli(alarmAtMillis).toString()
                } else null,
                "mission_status" to if (monitorMode == "alarm_with_mission") "pending" else "unconfigured",
            )
        }

        fun stopCurrent(reason: String): Map<String, Any?> {
            val service = activeInstance
            if (service != null) {
                service.finish(reason, "completed")
                return service.stateMap()
            }
            return lastState ?: mapOf("status" to "idle")
        }

        fun discardCurrent(): Map<String, Any?> {
            val service = activeInstance
            if (service != null) {
                service.finish("user", "discarded")
                return service.stateMap()
            }
            return lastState ?: mapOf("status" to "idle")
        }

        fun updateAlarm(alarmAtMillis: Long): Map<String, Any?> {
            val service = activeInstance ?: return lastState ?: mapOf("status" to "idle")
            service.updateAlarmInternal(alarmAtMillis)
            return service.stateMap()
        }

        fun alarmDismissed(context: android.content.Context, method: String) {
            val service = activeInstance
            service?.markAlarmDismissed(method)
            val snapshot = SleepAlarmScheduler.read(context)
            if (service == null && snapshot != null) {
                try {
                    val spool = SleepSessionSpool(context)
                    val stored = spool.read(snapshot.sessionId)
                    @Suppress("UNCHECKED_CAST")
                    val session: MutableMap<String, Any?> =
                        (stored["session"] as? Map<String, Any?>)?.toMutableMap()
                            ?: mutableMapOf()
                    session["alarm_dismiss_method"] = method
                    session["alarm_dismissed_at"] = Instant.now().toString()
                    session["mission_status"] = "completed"
                    spool.updateSession(session)
                } catch (_: Throwable) {
                    // The spool will still be imported with the completed alarm
                    // state on the next Flutter launch.
                }
            }
            val updated = (lastState ?: mapOf(
                "supported" to true,
                "status" to "completed",
            )) + mapOf(
                "alarm_dismissed" to true,
                "alarm_dismiss_method" to method,
                "alarm_ringing" to false,
                "mission_status" to "completed",
                "session_id" to snapshot?.sessionId,
                "end_reason" to "alarm",
            )
            lastState = updated
            eventSink?.invoke(updated)
        }

        fun publishAlarmRinging(context: android.content.Context) {
            val snapshot = SleepAlarmScheduler.read(context)
            val updated = (lastState ?: currentState(context)) + mapOf(
                "alarm_ringing" to true,
                "emergency_taps" to SleepAlarmScheduler.emergencyTaps(context),
                "monitor_mode" to (snapshot?.monitorMode ?: "alarm_without_mission"),
                "mission_status" to if (snapshot?.requiresMission == true) {
                    "pending"
                } else {
                    "unconfigured"
                },
                "alarm_at" to snapshot?.alarmAtMillis?.let {
                    Instant.ofEpochMilli(it).toString()
                },
                "session_id" to snapshot?.sessionId,
                "alarm_dismissed" to false,
                "alarm_dismiss_method" to null,
                "end_reason" to "alarm",
            )
            lastState = updated
            eventSink?.invoke(updated)
        }

        fun currentState(context: android.content.Context): Map<String, Any?> {
            val service = activeInstance
            if (service != null) return service.stateMap()
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
            val snapshot = SleepAlarmScheduler.read(context)
            if (lastState == null && snapshot?.state == SleepAlarmScheduler.STATE_RINGING) {
                return state(context, "completed", granted) + mapOf(
                    "session_id" to snapshot.sessionId,
                    "alarm_at" to Instant.ofEpochMilli(snapshot.alarmAtMillis).toString(),
                    "monitor_mode" to snapshot.monitorMode,
                    "mission_status" to if (snapshot.requiresMission) "pending" else "unconfigured",
                    "alarm_ringing" to true,
                    "emergency_taps" to SleepAlarmScheduler.emergencyTaps(context),
                )
            }
            return lastState ?: state(context, "idle", granted)
        }

        private fun state(
            context: android.content.Context,
            status: String,
            microphoneGranted: Boolean,
        ): Map<String, Any?> = mapOf(
            "supported" to true,
            "microphone_granted" to microphoneGranted,
            "status" to status,
            "updated_at" to Instant.now().toString(),
            "exact_alarm_granted" to SleepAlarmScheduler.canScheduleExact(context),
            "full_screen_intent_granted" to
                SleepAlarmScheduler.canUseFullScreenIntent(context),
        )
    }

    private lateinit var spool: SleepSessionSpool
    private var session: MutableMap<String, Any?>? = null
    private var processor: AudioSignalProcessor? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var finished = false
    @Volatile private var finishing = false
    private var latestSegment: Map<String, Any?>? = null
    private var noiseScore: Double? = null
    private var quietSeconds = 0
    private var noisySeconds = 0
    private var noiseEvents = 0
    private var inNoiseEvent = false
    private var validFractionSum = 0.0
    private var segmentCount = 0
    private var monitorMode = "alarm_without_mission"
    private var missionType: String? = null
    private var missionHash: String? = null
    private var missionSalt: String? = null
    private var missionFormat: String? = null

    override fun onCreate() {
        super.onCreate()
        spool = SleepSessionSpool(this)
        activeInstance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == SleepMonitorNotification.ACTION_STOP) {
            finish("notification_action", "completed")
            return START_NOT_STICKY
        }
        if (session != null) return START_NOT_STICKY

        // Foreground first: Android requires this immediately for a microphone
        // service, even though AudioRecord is opened only below after permission.
        monitorMode = intent?.getStringExtra(SleepAlarmScheduler.EXTRA_MONITOR_MODE)
            ?: "alarm_without_mission"
        missionType = intent?.getStringExtra(SleepAlarmScheduler.EXTRA_MISSION_TYPE)
        missionHash = intent?.getStringExtra(SleepAlarmScheduler.EXTRA_MISSION_HASH)
        missionSalt = intent?.getStringExtra(SleepAlarmScheduler.EXTRA_MISSION_SALT)
        missionFormat = intent?.getStringExtra(SleepAlarmScheduler.EXTRA_MISSION_FORMAT)
        SleepMonitorNotification.ensureChannel(this)
        val startedAt = System.currentTimeMillis()
        val notification = SleepMonitorNotification.build(this, startedAt, monitorMode)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                SleepMonitorNotification.NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(SleepMonitorNotification.NOTIFICATION_ID, notification)
        }

        val sessionId = intent?.getStringExtra(SleepAlarmScheduler.EXTRA_SESSION_ID)
            ?: UUID.randomUUID().toString()
        val alarmAtMillis = intent?.getLongExtra(
            SleepAlarmScheduler.EXTRA_ALARM_AT,
            0L,
        ) ?: 0L
        val start = Instant.ofEpochMilli(startedAt)
        val offset = ZoneId.systemDefault().rules.getOffset(start).totalSeconds / 60
        session = mutableMapOf(
            "id" to sessionId,
            "sleep_entry_id" to null,
            "status" to "starting",
            "started_at" to start.toString(),
            "ended_at" to null,
            "alarm_at" to if (alarmAtMillis > 0L) {
                Instant.ofEpochMilli(alarmAtMillis).toString()
            } else {
                null
            },
            "monitor_mode" to monitorMode,
            "mission_type" to missionType,
            "mission_status" to if (monitorMode == "alarm_with_mission") "pending" else "unconfigured",
            "alarm_dismiss_method" to null,
            "alarm_dismissed_at" to null,
            "utc_offset_start_minutes" to offset,
            "utc_offset_end_minutes" to null,
            "sensor_mode" to "audio",
            "algorithm_version" to "audio-noise-v1",
            "time_in_bed_minutes" to null,
            "quiet_minutes" to null,
            "noisy_minutes" to null,
            "estimated_sleep_minutes" to null,
            "noise_event_count" to 0,
            "signal_quality_score" to null,
            "analysis_status" to if (
                SleepStageModelGate.capabilities(this)["sleep_staging_available"] == true
            ) "pending" else "model_unavailable",
            "stage_algorithm_version" to null,
            "end_reason" to null,
            "created_at" to start.toString(),
        )
        spool.create(session!!)
        publish()

        if (!hasMicrophonePermission()) {
            finish("permission_revoked", "failed")
            return START_NOT_STICKY
        }

        try {
            acquireWakeLock()
            processor = AudioSignalProcessor(
                sessionId,
                onSegment = ::onSegment,
                onError = { finish("audio_error", "failed") },
            )
            processor?.start()
            session!!["status"] = "running"
            spool.updateSession(session!!)
            publish()
        } catch (_: Throwable) {
            finish("audio_error", "failed")
        }
        return START_NOT_STICKY
    }

    private fun onSegment(segment: Map<String, Any?>) {
        val current = session ?: return
        if (finished) return
        val startedMillis = Instant.parse(current["started_at"].toString()).toEpochMilli()
        if (!finishing) {
            if (!hasMicrophonePermission()) {
                finish("permission_revoked", "failed")
                return
            }
            if (System.currentTimeMillis() - startedMillis >= MAX_SESSION_MILLIS) {
                finish("time_limit", "completed")
                return
            }
        }
        latestSegment = segment
        noiseScore = (segment["noise_score"] as? Number)?.toDouble()
        val duration = (segment["duration_seconds"] as? Number)?.toInt() ?: 0
        val classification = segment["classification"]?.toString()
        if (classification == "quiet") quietSeconds += duration
        if (classification == "noise") noisySeconds += duration
        if (classification == "noise" && !inNoiseEvent) noiseEvents++
        inNoiseEvent = classification == "noise"
        validFractionSum += (segment["valid_fraction"] as? Number)?.toDouble() ?: 0.0
        segmentCount++
        current["quiet_minutes"] = (quietSeconds / 60.0).roundToInt()
        current["noisy_minutes"] = (noisySeconds / 60.0).roundToInt()
        current["noise_event_count"] = noiseEvents
        current["signal_quality_score"] = if (segmentCount == 0) 0.0 else validFractionSum / segmentCount
        current["time_in_bed_minutes"] = ((System.currentTimeMillis() - startedMillis) / 60_000.0).roundToInt()
        spool.appendSegment(segment)
        spool.updateSession(current)
        publish()
    }

    @Synchronized
    private fun finish(reason: String, finalStatus: String) {
        if (finished || finishing) return
        finishing = true
        val current = session
        if (current != null && finalStatus == "completed") {
            current["status"] = "stopping"
            spool.updateSession(current)
            publish()
        }
        if (current != null) {
            // stop() emits the final partial window. Keep onSegment enabled
            // until this returns so the last seconds are durably spooled.
            try { processor?.stop() } catch (_: Throwable) {}
            processor = null
            val endedMillis = System.currentTimeMillis()
            val ended = Instant.ofEpochMilli(endedMillis)
            val elapsedMillis =
                endedMillis - Instant.parse(current["started_at"].toString()).toEpochMilli()
            val completedWithoutData =
                finalStatus == "completed" &&
                segmentCount == 0 &&
                elapsedMillis >= AudioSignalProcessor.NO_DATA_TIMEOUT_MILLIS
            current["status"] = if (completedWithoutData) "failed" else finalStatus
            current["ended_at"] = ended.toString()
            current["end_reason"] = if (completedWithoutData) "no_audio_data" else reason
            current["time_in_bed_minutes"] = if (elapsedMillis <= 0) {
                0
            } else {
                ceil(elapsedMillis / 60_000.0).toInt()
            }
            current["quiet_minutes"] = (quietSeconds / 60.0).roundToInt()
            current["noisy_minutes"] = (noisySeconds / 60.0).roundToInt()
            current["noise_event_count"] = noiseEvents
            current["signal_quality_score"] =
                if (segmentCount == 0) 0.0 else validFractionSum / segmentCount
            val endOffset = ZoneId.systemDefault().rules.getOffset(ended).totalSeconds / 60
            current["utc_offset_end_minutes"] = endOffset
            spool.updateSession(current)
        }
        finished = true
        finishing = false
        if (
            (reason == "user" ||
                reason == "notification_action" ||
                finalStatus == "discarded") &&
                monitorMode != "alarm_with_mission"
        ) {
            SleepAlarmScheduler.cancel(this)
        }
        releaseResources()
        publish()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun releaseResources() {
        processor = null
        wakeLock?.let { lock ->
            if (lock.isHeld) lock.release()
        }
        wakeLock = null
        activeInstance = null
        lastState = session?.let { stateMap() }
    }

    private fun acquireWakeLock() {
        val manager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = manager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "WorkoutNotes:SleepMonitoring",
        ).apply { acquire(MAX_SESSION_MILLIS) }
    }

    private fun hasMicrophonePermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun stateMap(): Map<String, Any?> = mapOf(
        "supported" to true,
        "microphone_granted" to hasMicrophonePermission(),
        "status" to (session?.get("status") ?: "idle"),
        "session_id" to session?.get("id"),
        "started_at" to session?.get("started_at"),
        "updated_at" to Instant.now().toString(),
        "alarm_at" to session?.get("alarm_at"),
        "monitor_mode" to (session?.get("monitor_mode") ?: monitorMode),
        "mission_status" to (session?.get("mission_status") ?: "unconfigured"),
        "alarm_ringing" to false,
        "emergency_taps" to 0,
        "alarm_dismiss_method" to session?.get("alarm_dismiss_method"),
        "exact_alarm_granted" to SleepAlarmScheduler.canScheduleExact(this),
        "full_screen_intent_granted" to SleepAlarmScheduler.canUseFullScreenIntent(this),
        "alarm_dismissed" to false,
        "latest_segment" to latestSegment,
        "current_noise_score" to noiseScore,
        "end_reason" to session?.get("end_reason"),
        "error_code" to if (session?.get("status") == "failed") {
            session?.get("end_reason")
        } else {
            null
        },
    )

    @Synchronized
    private fun updateAlarmInternal(alarmAtMillis: Long) {
        val current = session ?: return
        if (finished || finishing) return
        current["alarm_at"] = Instant.ofEpochMilli(alarmAtMillis).toString()
        spool.updateSession(current)
        publish()
    }

    private fun publish() {
        val map = stateMap()
        lastState = map
        eventSink?.invoke(map)
    }

    private fun markAlarmDismissed(method: String) {
        val current = session ?: return
        current["alarm_dismiss_method"] = method
        current["alarm_dismissed_at"] = Instant.now().toString()
        current["mission_status"] = "completed"
        spool.updateSession(current)
    }

    override fun onDestroy() {
        if (!finished && session != null) finish("service_destroyed", "interrupted")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
