package com.workoutnotes.workout_notes.sleep

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicReference

class SleepMonitorBridge(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    companion object { const val PERMISSION_REQUEST_CODE = 8451 }

    private var activity: Activity? = null
    private val pendingPermission = AtomicReference<MethodChannel.Result?>(null)
    private val spool by lazy { SleepSessionSpool(context.applicationContext) }

    fun attachActivity(value: Activity) { activity = value }
    fun detachActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(
                mapOf(
                    "supported" to true,
                    "microphone_granted" to microphoneGranted(),
                    "notifications_permission_required" to (Build.VERSION.SDK_INT >= 33),
                    "device_manufacturer" to Build.MANUFACTURER,
                    "device_model" to Build.MODEL,
                    "android_sdk_int" to Build.VERSION.SDK_INT,
                    "android_release" to Build.VERSION.RELEASE,
                ),
            )
            "getState" -> result.success(SleepMonitoringService.currentState(context))
            "requestMicrophonePermission" -> requestMicrophonePermission(result)
            "startMonitoring" -> startMonitoring(result)
            "stopMonitoring" -> result.success(SleepMonitoringService.stopCurrent("user"))
            "discardSession" -> {
                SleepMonitoringService.discardCurrent()
                val id = call.arguments as? String
                if (id != null) spool.delete(id)
                result.success(null)
            }
            "listPendingSessions" -> result.success(spool.listPending())
            "readSession" -> {
                val id = call.arguments as? String
                if (id == null) result.error("invalid_id", "Missing session id", null)
                else {
                    try { result.success(spool.read(id)) }
                    catch (error: Throwable) { result.error("read_failed", error.message, null) }
                }
            }
            "deleteSpool" -> {
                val id = call.arguments as? String
                if (id != null) spool.delete(id)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestMicrophonePermission(result: MethodChannel.Result) {
        if (microphoneGranted()) {
            result.success(true)
            return
        }
        val visibleActivity = activity
        if (visibleActivity == null) {
            result.error("activity_unavailable", "A visible Activity is required", null)
            return
        }
        if (!pendingPermission.compareAndSet(null, result)) {
            result.error("permission_pending", "Permission request already pending", null)
            return
        }
        visibleActivity.requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            PERMISSION_REQUEST_CODE,
        )
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val result = pendingPermission.getAndSet(null)
        result?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        return true
    }

    private fun startMonitoring(result: MethodChannel.Result) {
        if (!microphoneGranted()) {
            result.error("microphone_denied", "Microphone permission denied", null)
            return
        }
        val activeSpool = spool.listPending().any {
            it["status"] == "starting" || it["status"] == "running" || it["status"] == "stopping"
        }
        if (activeSpool) {
            result.error("already_active", "A monitoring session is already active", null)
            return
        }
        val intent = Intent(context, SleepMonitoringService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        result.success(SleepMonitoringService.startResponse(context))
    }

    private fun microphoneGranted(): Boolean = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val mainHandler = Handler(Looper.getMainLooper())
        SleepMonitoringService.eventSink = { event ->
            mainHandler.post { events?.success(event) }
        }
        events?.success(SleepMonitoringService.currentState(context))
    }

    override fun onCancel(arguments: Any?) {
        SleepMonitoringService.eventSink = null
    }
}
