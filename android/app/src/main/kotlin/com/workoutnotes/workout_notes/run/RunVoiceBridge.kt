package com.workoutnotes.workout_notes.run

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class RunVoiceBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    // Pending config that RunTrackingService will pick up on start.
    companion object {
        @Volatile var pendingSettings: Map<String, Any?>? = null
        @Volatile var pendingGoal: Map<String, Any?>? = null
        @Volatile var pendingIntervalsOn: Boolean? = null

        /** Structured plan steps waiting for the tracking service to start. */
        @Volatile var pendingPlan: Any? = null
    }

    private fun voiceController(): RunVoiceController {
        // Service companion holds singleton; bridge creates ephemeral controller for testSpeak when no service.
        val service = RunTrackingService.activeInstanceForVoice()
        return service?.voiceController ?: ephemeralController()
    }

    /**
     * Controller for one-shot announcements outside a live session. Settings
     * come from the call when Flutter sends them, else from the pending sync
     * or storage.
     */
    private fun preparedController(call: MethodCall): RunVoiceController {
        val ctrl = voiceController()
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val settingsMap = args?.get("settings") as? Map<String, Any?>
        when {
            settingsMap != null -> ctrl.syncFromFlutter(settingsMap, null, null)
            pendingSettings != null -> ctrl.syncFromFlutter(pendingSettings, pendingGoal, pendingIntervalsOn)
            else -> ctrl.loadSettingsFromDb()
        }
        return ctrl
    }

    private var ephemeral: RunVoiceController? = null
    private fun ephemeralController(): RunVoiceController {
        var ctrl = ephemeral
        if (ctrl == null) {
            ctrl = RunVoiceController(context.applicationContext)
            ephemeral = ctrl
        }
        return ctrl
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "syncSettings" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                @Suppress("UNCHECKED_CAST")
                val settingsMap = args["settings"] as? Map<String, Any?>
                @Suppress("UNCHECKED_CAST")
                val goalMap = args["goal"] as? Map<String, Any?>
                val intervalsOn = args["intervalsOn"] as? Boolean
                val plan = args["plan"]
                pendingSettings = settingsMap
                pendingGoal = goalMap
                pendingIntervalsOn = intervalsOn
                if (args.containsKey("plan")) pendingPlan = plan
                // If service already running, push immediately
                val svc = RunTrackingService.activeInstanceForVoice()
                if (svc != null) {
                    svc.voiceController.syncFromFlutter(settingsMap, goalMap, intervalsOn, plan)
                }
                Log.i("RunVoiceBridge", "syncSettings intervalsOn=$intervalsOn")
                result.success(null)
            }
            "beginSession" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                @Suppress("UNCHECKED_CAST")
                val settingsMap = args["settings"] as? Map<String, Any?>
                @Suppress("UNCHECKED_CAST")
                val goalMap = args["goal"] as? Map<String, Any?>
                val intervalsOn = args["intervalsOn"] as? Boolean
                val plan = args["plan"]
                val svc = RunTrackingService.activeInstanceForVoice()
                if (svc != null) {
                    svc.voiceController.begin(settingsMap, goalMap, intervalsOn, plan)
                    svc.persistVoicePlan()
                } else {
                    // No service yet — store pending, will be consumed on startRun
                    pendingSettings = settingsMap
                    pendingGoal = goalMap
                    pendingIntervalsOn = intervalsOn
                        pendingPlan = plan
                    // Also init ephemeral to allow test-like warm-up
                    ephemeralController().begin(settingsMap, goalMap, intervalsOn, plan)
                }
                result.success(null)
            }
            "endSession" -> {
                val svc = RunTrackingService.activeInstanceForVoice()
                svc?.voiceController?.end()
                ephemeral?.end()
                pendingSettings = null
                pendingGoal = null
                pendingIntervalsOn = null
                pendingPlan = null
                result.success(null)
            }
            "skipStep" -> {
                val svc = RunTrackingService.activeInstanceForVoice()
                result.success(svc?.skipStep() ?: false)
            }
            "stepResults" -> {
                // Native is the source of truth for a structured session: it keeps
                // cueing (and measuring) while the Flutter engine is dead.
                val svc = RunTrackingService.activeInstanceForVoice()
                val controller = svc?.voiceController ?: ephemeral
                result.success(controller?.stepResults() ?: emptyList<Map<String, Any?>>())
            }
            "speakTest" -> {
                val ctrl = preparedController(call)
                ctrl.speakTest()
                result.success(true)
            }
            "speakWorkoutComplete" -> {
                val ctrl = preparedController(call)
                ctrl.speakWorkoutComplete()
                result.success(true)
            }
            "getCapabilities" -> {
                // Reuse audio gate logic for Flutter UI
                val am = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                val headset = try {
                    val devices = am.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
                    devices.any {
                        it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                            it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                            it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                            it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            it.type == android.media.AudioDeviceInfo.TYPE_USB_HEADSET
                    }
                } catch (_: Throwable) { false }
                val inCall = when (am.mode) {
                    android.media.AudioManager.MODE_IN_CALL, android.media.AudioManager.MODE_IN_COMMUNICATION -> true
                    else -> false
                }
                result.success(mapOf("headset_connected" to headset, "in_call" to inCall))
            }
            else -> result.notImplemented()
        }
    }
}
