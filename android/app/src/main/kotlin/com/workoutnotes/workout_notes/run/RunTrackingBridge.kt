package com.workoutnotes.workout_notes.run

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class RunTrackingBridge(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    companion object {
        const val LOCATION_PERMISSION_REQUEST_CODE = 8461
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 8462

        /** Context waiting for the foreground service to create its spool. */
        @Volatile var pendingSessionContext: Map<String, Any?>? = null
    }

    private var activity: Activity? = null
    private val pendingLocationPermission = AtomicReference<MethodChannel.Result?>(null)
    private val pendingNotificationPermission = AtomicReference<MethodChannel.Result?>(null)
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
                    "notifications_granted" to notificationPermissionGranted(),
                    "notifications_permission_required" to (Build.VERSION.SDK_INT >= 33),
                    // A run is started while the Activity is visible and then kept
                    // alive by a location foreground service. Background location
                    // is therefore neither declared nor requested.
                    "background_location_required" to false,
                    "android_sdk_int" to Build.VERSION.SDK_INT,
                ),
            )
            "getState" -> result.success(RunTrackingService.currentState(context))
            "requestLocationPermission" -> requestLocationPermission(result)
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "openAppSettings" -> openAppSettings(result)
            "getCurrentLocation" -> getCurrentLocation(result)
            "setSessionContext" -> setSessionContext(call, result)
            "recoverActive" -> recoverActive(result)
            "start" -> start(result)
            "startDebugSimulation" -> startDebugSimulation(call, result)
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
            "markPendingReview" -> {
                val id = call.arguments as? String
                if (id == null) {
                    result.error("invalid_id", "Missing activity id", null)
                } else {
                    try {
                        val raw = spool.read(id)
                        @Suppress("UNCHECKED_CAST")
                        val activity = (raw["activity"] as? Map<String, Any?>)
                            ?.toMutableMap()
                            ?: mutableMapOf()
                        activity["id"] = id
                        activity["status"] = "pending_review"
                        spool.updateActivity(activity)
                        result.success(mapOf("activity" to activity, "points" to raw["points"]))
                    } catch (error: Throwable) {
                        result.error("review_failed", error.message, null)
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

    private fun setSessionContext(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val value = call.arguments as? Map<String, Any?> ?: emptyMap()
        pendingSessionContext = value
        RunTrackingService.activeInstanceForVoice()?.persistSessionContext(value)
        result.success(null)
    }

    /** Proactively reattaches an active spool when Flutter opens before the
     * system has delivered the service's START_STICKY restart. */
    private fun recoverActive(result: MethodChannel.Result) {
        if (RunTrackingService.activeInstanceForVoice() != null) {
            result.success(true)
            return
        }
        val hasActiveSpool = spool.listPending().any {
            when (it["status"] as? String) {
                "starting", "recording", "paused", "stopping" -> true
                else -> false
            }
        }
        if (!hasActiveSpool) {
            result.success(false)
            return
        }
        val intent = Intent(context, RunTrackingService::class.java).apply {
            action = RunTrackingService.ACTION_RESTORE
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            result.success(true)
        } catch (error: Throwable) {
            result.error("restore_failed", error.message, null)
        }
    }

    /** One high-accuracy fix while the run screen is visible, before timing. */
    private fun getCurrentLocation(result: MethodChannel.Result) {
        if (!RunTrackingService.locationGranted(context)) {
            result.error("location_denied", "Precise location permission denied", null)
            return
        }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val provider = when {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> {
                result.error("location_disabled", "Location services are disabled", null)
                return
            }
        }
        val delivered = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        var fallback: Location? = null
        try {
            fallback = manager.getLastKnownLocation(provider)
        } catch (_: SecurityException) {
        }

        fun locationMap(location: Location): Map<String, Any?> = mapOf(
            "lat" to location.latitude,
            "lng" to location.longitude,
            "accuracy_meters" to if (location.hasAccuracy()) location.accuracy.toDouble() else null,
            "recorded_at_millis" to location.time,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val cancellation = CancellationSignal()
            handler.postDelayed({
                if (delivered.compareAndSet(false, true)) {
                    cancellation.cancel()
                    val last = fallback
                    if (last != null) result.success(locationMap(last))
                    else result.error("gps_timeout", "No GPS fix available", null)
                }
            }, 8_000L)
            try {
                manager.getCurrentLocation(provider, cancellation, context.mainExecutor) { location ->
                    if (location != null && delivered.compareAndSet(false, true)) {
                        result.success(locationMap(location))
                    }
                }
            } catch (error: SecurityException) {
                if (delivered.compareAndSet(false, true)) {
                    result.error("location_denied", error.message, null)
                }
            }
            return
        }

        @Suppress("DEPRECATION")
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                manager.removeUpdates(this)
                if (delivered.compareAndSet(false, true)) {
                    result.success(locationMap(location))
                }
            }
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        handler.postDelayed({
            try {
                manager.removeUpdates(listener)
            } catch (_: SecurityException) {
            }
            if (delivered.compareAndSet(false, true)) {
                val last = fallback
                if (last != null) result.success(locationMap(last))
                else result.error("gps_timeout", "No GPS fix available", null)
            }
        }, 8_000L)
        try {
            @Suppress("DEPRECATION")
            manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
        } catch (error: SecurityException) {
            if (delivered.compareAndSet(false, true)) {
                result.error("location_denied", error.message, null)
            }
        }
    }

    private fun startDebugSimulation(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any?> ?: emptyMap()
        val startLat = (args["startLat"] as? Number)?.toDouble() ?: -23.5505
        val startLng = (args["startLng"] as? Number)?.toDouble() ?: -46.6333
        val active = spool.listPending().any {
            val status = it["status"] as? String
            status == "starting" || status == "recording" || status == "paused" || status == "stopping"
        }
        val current = RunTrackingService.currentState(context)["status"] as? String
        if (active || current == "recording" || current == "paused" || current == "starting") {
            result.error("already_active", "A run is already active", null)
            return
        }
        // Debug sim bypasses location permission — uses synthetic GPS.
        val service = RunTrackingService.activeInstanceForVoice()
        if (service != null) {
            val ok = service.startNativeDebugSimulation(startLat, startLng)
            result.success(ok)
            return
        }
        // No active service — start via intent with debug extras.
        val intent = Intent(context, RunTrackingService::class.java).apply {
            action = "com.workoutnotes.workout_notes.run.START_DEBUG"
            putExtra("debug_start_lat", startLat)
            putExtra("debug_start_lng", startLng)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        result.success(true)
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
        if (!pendingLocationPermission.compareAndSet(null, result)) {
            result.error("permission_pending", "Permission request already pending", null)
            return
        }
        visibleActivity.requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            LOCATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun notificationPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (notificationPermissionGranted()) {
            result.success(true)
            return
        }
        val visibleActivity = activity
        if (visibleActivity == null) {
            result.error("activity_unavailable", "A visible Activity is required", null)
            return
        }
        if (!pendingNotificationPermission.compareAndSet(null, result)) {
            result.error("permission_pending", "Permission request already pending", null)
            return
        }
        visibleActivity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
            result.success(true)
        } catch (error: Throwable) {
            result.error("settings_unavailable", error.message, null)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        when (requestCode) {
            LOCATION_PERMISSION_REQUEST_CODE -> {
                val result = pendingLocationPermission.getAndSet(null)
                // Fine location is required; coarse-only is treated as denied.
                val granted = grantResults.isNotEmpty() &&
                    ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.ACCESS_FINE_LOCATION,
                    ) == PackageManager.PERMISSION_GRANTED
                result?.success(granted)
                return true
            }
            NOTIFICATION_PERMISSION_REQUEST_CODE -> {
                val result = pendingNotificationPermission.getAndSet(null)
                val granted = notificationPermissionGranted()
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
