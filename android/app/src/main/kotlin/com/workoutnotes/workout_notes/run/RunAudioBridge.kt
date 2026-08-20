package com.workoutnotes.workout_notes.run

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reports headset connectivity and in-call audio mode for run TTS gating.
 * Uses AudioManager only — no READ_PHONE_STATE permission.
 */
class RunAudioBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                result.success(
                    mapOf(
                        "headset_connected" to isHeadsetConnected(am),
                        "in_call" to isInCall(am),
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun isInCall(am: AudioManager): Boolean {
        return when (am.mode) {
            AudioManager.MODE_IN_CALL,
            AudioManager.MODE_IN_COMMUNICATION,
            -> true
            else -> false
        }
    }

    private fun isHeadsetConnected(am: AudioManager): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (device in devices) {
                when (device.type) {
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_USB_HEADSET,
                    AudioDeviceInfo.TYPE_HEARING_AID,
                    -> return true
                    else -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            if (device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                                device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                            ) {
                                return true
                            }
                        }
                    }
                }
            }
            return false
        }
        @Suppress("DEPRECATION")
        return am.isWiredHeadsetOn || am.isBluetoothA2dpOn || am.isBluetoothScoOn
    }
}
