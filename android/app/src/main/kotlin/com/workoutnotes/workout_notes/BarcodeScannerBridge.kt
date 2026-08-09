package com.workoutnotes.workout_notes

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicReference
import com.workoutnotes.workout_notes.sleep.BarcodeScannerActivity

/**
 * Flutter bridge for the nutrition module's barcode scanner.
 *
 * Launches [BarcodeScannerActivity] in raw-value mode (no enrollment)
 * and returns the scanned value + format to Dart.
 */
class BarcodeScannerBridge : MethodChannel.MethodCallHandler {
    companion object {
        const val SCAN_REQUEST_CODE = 9154
        private const val DEFAULT_TIMEOUT_MILLIS = 60_000L
    }

    private var activity: Activity? = null
    private val pendingScan = AtomicReference<MethodChannel.Result?>(null)

    fun attachActivity(value: Activity) {
        activity = value
    }

    fun detachActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scan" -> scan(result)
            else -> result.notImplemented()
        }
    }

    private fun scan(result: MethodChannel.Result) {
        val visibleActivity = activity
        if (visibleActivity == null) {
            result.error("activity_unavailable", "A visible Activity is required", null)
            return
        }
        if (!pendingScan.compareAndSet(null, result)) {
            result.error("scan_pending", "A barcode scan is already pending", null)
            return
        }
        visibleActivity.startActivityForResult(
            Intent(visibleActivity, BarcodeScannerActivity::class.java).apply {
                putExtra(BarcodeScannerActivity.EXTRA_ENROLLMENT, false)
                putExtra(BarcodeScannerActivity.EXTRA_TIMEOUT_MILLIS, DEFAULT_TIMEOUT_MILLIS)
            },
            SCAN_REQUEST_CODE,
        )
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SCAN_REQUEST_CODE) return false
        val result = pendingScan.getAndSet(null)
        if (result == null) return true
        if (resultCode != BarcodeScannerActivity.RESULT_SUCCESS || data == null) {
            result.success(null)
            return true
        }
        result.success(
            mapOf(
                "value" to (data.getStringExtra(BarcodeScannerActivity.EXTRA_RAW_VALUE) ?: ""),
                "format" to (data.getStringExtra(BarcodeScannerActivity.EXTRA_FORMAT) ?: ""),
            ),
        )
        return true
    }
}
