package com.workoutnotes.workout_notes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.workoutnotes.workout_notes.run.RunTrackingBridge
import com.workoutnotes.workout_notes.sleep.SleepMonitorBridge
import com.workoutnotes.workout_notes.sleep.TraditionalAlarmBridge

class MainActivity : FlutterActivity() {
    private var sleepMonitorBridge: SleepMonitorBridge? = null
    private var runTrackingBridge: RunTrackingBridge? = null
    private var barcodeScannerBridge: BarcodeScannerBridge? = null
    private lateinit var traditionalAlarmBridge: TraditionalAlarmBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = SleepMonitorBridge(this)
        sleepMonitorBridge = bridge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "workout_notes/sleep_monitor/methods",
        ).setMethodCallHandler(bridge)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "workout_notes/sleep_monitor/events",
        ).setStreamHandler(bridge)
        val runBridge = RunTrackingBridge(this)
        runTrackingBridge = runBridge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "workout_notes/run_tracking/methods",
        ).setMethodCallHandler(runBridge)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "workout_notes/run_tracking/events",
        ).setStreamHandler(runBridge)
        val barcodeBridge = BarcodeScannerBridge()
        barcodeScannerBridge = barcodeBridge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "workout_notes/barcode_scanner/methods",
        ).setMethodCallHandler(barcodeBridge)
        traditionalAlarmBridge = TraditionalAlarmBridge(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "workout_notes/traditional_alarms/methods",
        ).setMethodCallHandler(traditionalAlarmBridge)
    }

    override fun onResume() {
        super.onResume()
        sleepMonitorBridge?.attachActivity(this)
        runTrackingBridge?.attachActivity(this)
        barcodeScannerBridge?.attachActivity(this)
    }

    override fun onPause() {
        sleepMonitorBridge?.detachActivity()
        runTrackingBridge?.detachActivity()
        barcodeScannerBridge?.detachActivity()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (sleepMonitorBridge?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        if (runTrackingBridge?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    @Deprecated("Deprecated in Android SDK")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        val handled = sleepMonitorBridge?.onActivityResult(requestCode, resultCode, data) == true ||
            barcodeScannerBridge?.onActivityResult(requestCode, resultCode, data) == true
        if (!handled) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
