package com.workoutnotes.workout_notes.sleep

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TraditionalAlarmBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "schedule" -> {
                    val id = call.argument<String>("id") ?: return result.error("invalid_id", "Missing alarm id", null)
                    val at = call.argument<Number>("alarm_at_epoch_ms")?.toLong() ?: return result.error("invalid_time", "Missing alarm time", null)
                    val days = (call.argument<List<Any>>("weekdays") ?: emptyList()).mapNotNull { (it as? Number)?.toInt() }.toSet()
                    val requiresMission = call.argument<Boolean>("requires_mission") ?: false
                    val hash = call.argument<String>("mission_hash")
                    val salt = call.argument<String>("mission_salt")
                    if (requiresMission && (hash.isNullOrBlank() || salt.isNullOrBlank())) return result.error("mission_not_configured", "Mission is not configured", null)
                    TraditionalAlarmScheduler.schedule(context, TraditionalAlarmScheduler.Snapshot(
                        id, at, call.argument<Int>("hour") ?: 7, call.argument<Int>("minute") ?: 0,
                        days, call.argument<Boolean>("snooze_enabled") ?: true,
                        call.argument<Int>("snooze_minutes") ?: 5,
                        (call.argument<Int>("max_snoozes") ?: 3).coerceIn(0, 10), 0, requiresMission,
                        hash, salt, call.argument<String>("mission_format"), "scheduled", true,
                    ))
                    result.success(null)
                }
                "cancel" -> {
                    val id = call.argument<String>("id") ?: return result.error("invalid_id", "Missing alarm id", null)
                    TraditionalAlarmScheduler.cancel(context, id); result.success(null)
                }
                "openSnoozedMission" -> {
                    val id = call.argument<String>("id") ?: return result.error("invalid_id", "Missing alarm id", null)
                    val current = TraditionalAlarmScheduler.read(context, id)
                    val snapshot = if (current != null && current.state == "ringing" && current.requiresMission) {
                        current
                    } else {
                        TraditionalAlarmScheduler.resumeSnoozedMission(context, id)
                    } ?: return result.error("invalid_state", "This alarm is not snoozing with a mission", null)
                    TraditionalAlarmRingingService.start(context, snapshot.id)
                    context.startActivity(Intent(context, TraditionalAlarmActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        putExtra(TraditionalAlarmScheduler.EXTRA_ID, snapshot.id)
                    })
                    result.success(null)
                }
                "dismissSnooze" -> {
                    val id = call.argument<String>("id") ?: return result.error("invalid_id", "Missing alarm id", null)
                    if (!TraditionalAlarmScheduler.dismissSnooze(context, id)) {
                        return result.error("invalid_state", "This alarm is not snoozing without a mission", null)
                    }
                    result.success(null)
                }
                "restore" -> { TraditionalAlarmScheduler.restore(context); result.success(null) }
                "states" -> result.success(TraditionalAlarmScheduler.states(context))
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) { result.error("exact_alarm_denied", error.message, null) }
        catch (error: Throwable) { result.error("schedule_failed", error.message, null) }
    }
}
