package com.workoutnotes.workout_notes.run

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
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference

class RunTrackingBridge(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    companion object {
        const val PERMISSION_REQUEST_CODE = 8461
        const val BACKGROUND_PERMISSION_REQUEST_CODE = 8462
    }

    private var activity: Activity? = null
    private val pendingPermission = AtomicReference<MethodChannel.Result?>(null)
    private val pendingBackgroundPermission = AtomicReference<MethodChannel.Result?>(null)
    private val spool by lazy { RunActivitySpool(context.applicationContext) }

    fun attachActivity(value: Activity) {
        activity = value
    }

    fun detachActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(
                mapOf(
                    "supported" to true,
                    "location_granted" to RunTrackingService.locationGranted(context),
                    "background_location_granted" to
                        RunTrackingService.backgroundLocationGranted(context),
                    "notifications_permission_required" to (Build.VERSION.SDK_INT >= 33),
                    "background_location_required" to (Build.VERSION.SDK_INT >= 29),
                    "android_sdk_int" to Build.VERSION.SDK_INT,
                ),
            )
            "getState" -> result.success(RunTrackingService.currentState(context))
            "requestPermissions" -> requestLocationPermission(result)
            "requestBackgroundPermission" -> requestBackgroundLocationPermission(result)
            "start" -> start(result)
            "pause" -> result.success(RunTrackingService.pauseCurrent())
            "resume" -> result.success(RunTrackingService.resumeCurrent())
            "stop" -> result.success(RunTrackingService.stopCurrent(context))
            "discard" -> {
                val id = call.arguments as? String
                val state = RunTrackingService.discardCurrent(context)
                if (id != null) {
                    try {
                        spool.delete(id)
                    } catch (_: Throwable) {
                    }
                }
                result.success(state)
            }
            "listPendingSpools" -> result.success(spool.listPending())
            "readSpool" -> {
                val id = call.arguments as? String
                if (id == null) {
                    result.error("invalid_id", "Missing activity id", null)
                } else {
                    try {
                        result.success(spool.read(id))
                    } catch (error: Throwable) {
                        result.error("read_failed", error.message, null)
                    }
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

    private fun start(result: MethodChannel.Result) {
        if (!RunTrackingService.locationGranted(context)) {
            result.error(
                "location_denied",
                "Precise location permission denied",
                null,
            )
            return
        }
        val active = spool.listPending().any {
            val status = it["status"] as? String
            status == "starting" || status == "recording" || status == "paused" || status == "stopping"
        }
        val current = RunTrackingService.currentState(context)["status"] as? String
        if (active || current == "recording" || current == "paused" || current == "starting") {
            result.error("already_active", "A run is already active", null)
            return
        }
        val activityId = UUID.randomUUID().toString()
        val intent = Intent(context, RunTrackingService::class.java).apply {
            action = RunTrackingService.ACTION_START
            putExtra(RunTrackingService.EXTRA_ACTIVITY_ID, activityId)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        result.success(
            mapOf(
                "supported" to true,
                "location_granted" to true,
                "status" to "starting",
                "activity_id" to activityId,
            ),
        )
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (RunTrackingService.locationGranted(context)) {
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
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        if (Build.VERSION.SDK_INT >= 33) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        visibleActivity.requestPermissions(
            permissions.toTypedArray(),
            PERMISSION_REQUEST_CODE,
        )
    }

    private fun requestBackgroundLocationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(true)
            return
        }
        if (RunTrackingService.backgroundLocationGranted(context)) {
            result.success(true)
            return
        }
        if (!RunTrackingService.locationGranted(context)) {
            result.error(
                "location_denied",
                "Precise location must be granted before background access",
                null,
            )
            return
        }
        val visibleActivity = activity
        if (visibleActivity == null) {
            result.error("activity_unavailable", "A visible Activity is required", null)
            return
        }
        if (!pendingBackgroundPermission.compareAndSet(null, result)) {
            result.error("permission_pending", "Permission request already pending", null)
            return
        }
        visibleActivity.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            BACKGROUND_PERMISSION_REQUEST_CODE,
        )
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        when (requestCode) {
            PERMISSION_REQUEST_CODE -> {
                val result = pendingPermission.getAndSet(null)
                // Fine location is required; coarse-only is treated as denied.
                val granted = grantResults.isNotEmpty() &&
                    ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.ACCESS_FINE_LOCATION,
                    ) == PackageManager.PERMISSION_GRANTED
                result?.success(granted)
                return true
            }
            BACKGROUND_PERMISSION_REQUEST_CODE -> {
                val result = pendingBackgroundPermission.getAndSet(null)
                val granted = RunTrackingService.backgroundLocationGranted(context)
                result?.success(granted)
                return true
            }
            else -> return false
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val mainHandler = Handler(Looper.getMainLooper())
        RunTrackingService.eventSink = { event ->
            mainHandler.post { events?.success(event) }
        }
        events?.success(RunTrackingService.currentState(context))
    }

    override fun onCancel(arguments: Any?) {
        RunTrackingService.eventSink = null
    }
}
