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
        @Volatile var pendingBypassGate: Boolean? = null
    }

    private fun voiceController(): RunVoiceController? {
        // Service companion holds singleton; bridge creates ephemeral controller for testSpeak when no service.
        val service = RunTrackingService.activeInstanceForVoice()
        return service?.voiceController ?: ephemeralController()
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
                val bypassGate = args["bypassHeadphonesGate"] as? Boolean
                pendingSettings = settingsMap
                pendingGoal = goalMap
                pendingIntervalsOn = intervalsOn
                pendingBypassGate = bypassGate
                // If service already running, push immediately
                val svc = RunTrackingService.activeInstanceForVoice()
                if (svc != null) {
                    svc.voiceController.syncFromFlutter(settingsMap, goalMap, intervalsOn, bypassGate)
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
                val bypassGate = args["bypassHeadphonesGate"] as? Boolean
                val svc = RunTrackingService.activeInstanceForVoice()
                if (svc != null) {
                    svc.voiceController.begin(settingsMap, goalMap, intervalsOn, bypassGate)
                } else {
                    // No service yet — store pending, will be consumed on startRun
                    pendingSettings = settingsMap
                    pendingGoal = goalMap
                    pendingIntervalsOn = intervalsOn
                    pendingBypassGate = bypassGate
                    // Also init ephemeral to allow test-like warm-up
                    ephemeralController().begin(settingsMap, goalMap, intervalsOn, bypassGate)
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
                pendingBypassGate = null
                result.success(null)
            }
            "speakTest" -> {
                val ctrl = voiceController()
                // Ensure settings are loaded
                if (ctrl != null) {
                    // If we have pending settings, apply
                    if (pendingSettings != null) {
                        ctrl.syncFromFlutter(pendingSettings, pendingGoal, pendingIntervalsOn, pendingBypassGate)
                    } else {
                        ctrl.loadSettingsFromDb()
                    }
                    ctrl.speakTest()
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "getCapabilities" -> {
                // Reuse audio gate logic for Flutter UI
                val am = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                val headset = try {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        val devices = am.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)
                        devices.any {
                            it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                                it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                                it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                                it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                                it.type == android.media.AudioDeviceInfo.TYPE_USB_HEADSET
                        }
                    } else {
                        @Suppress("DEPRECATION")
                        am.isWiredHeadsetOn || am.isBluetoothA2dpOn || am.isBluetoothScoOn
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
