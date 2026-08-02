package com.workoutnotes.workout_notes.sleep

import android.content.Context
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
                "restore" -> { TraditionalAlarmScheduler.restore(context); result.success(null) }
                "states" -> result.success(TraditionalAlarmScheduler.states(context))
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) { result.error("exact_alarm_denied", error.message, null) }
        catch (error: Throwable) { result.error("schedule_failed", error.message, null) }
    }
}
