package com.workoutnotes.workout_notes.medication

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** `workout_notes/medication/methods`: Dart ↔ native medication reminders. */
class MedicationReminderBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "schedule" -> {
                    val id = call.argument<String>("slot_id")
                        ?: return result.error("invalid_id", "Missing slot id", null)
                    val medicationId = call.argument<String>("medication_id")
                        ?: return result.error("invalid_id", "Missing medication id", null)
                    val weekdays = (call.argument<List<Any>>("weekdays") ?: emptyList())
                        .mapNotNull { (it as? Number)?.toInt() }
                        .toSet()
                    MedicationReminderScheduler.schedule(
                        context,
                        id = id,
                        medicationId = medicationId,
                        name = call.argument<String>("name") ?: "",
                        dosage = call.argument<String>("dosage"),
                        hour = call.argument<Int>("hour") ?: 8,
                        minute = call.argument<Int>("minute") ?: 0,
                        weekdays = weekdays,
                        escalationMinutes = call.argument<Int>("escalation_minutes") ?: 30,
                    )
                    result.success(null)
                }
                "cancel" -> {
                    val id = call.argument<String>("slot_id")
                        ?: return result.error("invalid_id", "Missing slot id", null)
                    MedicationReminderScheduler.cancel(context, id)
                    result.success(null)
                }
                "confirm" -> {
                    val id = call.argument<String>("slot_id")
                        ?: return result.error("invalid_id", "Missing slot id", null)
                    val key = call.argument<String>("dose_key")
                        ?: return result.error("invalid_dose", "Missing dose key", null)
                    val status = call.argument<String>("status") ?: MedicationReminderScheduler.STATUS_TAKEN
                    result.success(
                        MedicationReminderScheduler.confirm(context, id, key, status, fromNative = false),
                    )
                }
                "states" -> result.success(MedicationReminderScheduler.states(context))
                "spool" -> result.success(MedicationReminderScheduler.spool(context))
                "ackSpool" -> {
                    val ids = (call.argument<List<Any>>("ids") ?: emptyList()).mapNotNull { it as? String }.toSet()
                    MedicationReminderScheduler.ackSpool(context, ids)
                    result.success(null)
                }
                "restore" -> {
                    MedicationReminderScheduler.restore(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("medication_failed", error.message, null)
        }
    }
}
