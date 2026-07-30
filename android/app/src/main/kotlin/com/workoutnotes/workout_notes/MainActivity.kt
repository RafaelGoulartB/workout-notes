package com.workoutnotes.workout_notes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.workoutnotes.workout_notes.sleep.SleepMonitorBridge

class MainActivity : FlutterActivity() {
    private var sleepMonitorBridge: SleepMonitorBridge? = null

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
    }

    override fun onResume() {
        super.onResume()
        sleepMonitorBridge?.attachActivity(this)
    }

    override fun onPause() {
        sleepMonitorBridge?.detachActivity()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (sleepMonitorBridge?.onRequestPermissionsResult(requestCode, grantResults) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
