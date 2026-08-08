package com.workoutnotes.workout_notes.sleep

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Accumulates actigraphy aggregates over each 30-second audio window.
 *
 * Prefers TYPE_LINEAR_ACCELERATION (gravity already removed) and falls back to
 * TYPE_ACCELEROMETER with gravity subtracted manually. If no sensor is
 * available, [available] stays false and audio-only scoring applies on the
 * Dart side. Motion events arrive on the main thread while [snapshotAndReset]
 * runs on the audio capture thread, so both methods share the instance monitor.
 */
class MotionAggregator(private val sensorManager: SensorManager?) : SensorEventListener {
    companion object {
        private const val GRAVITY_MPS2 = 9.81
        private const val ACTIVE_THRESHOLD_G = 0.05

        fun from(context: Context): MotionAggregator {
            val manager =
                context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
            return MotionAggregator(manager)
        }
    }

    var available: Boolean = false
        private set
    private var registered = false
    private var activeSeconds = 0.0
    private var activeWindowStartedMillis = 0L
    private var sumDeviation = 0.0
    private var maxDeviation = 0.0
    private var sampleCount = 0L

    fun register() {
        if (registered || sensorManager == null) return
        val sensor = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            ?: return
        available = true
        registered = true
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
    }

    fun unregister() {
        if (!registered) return
        registered = false
        sensorManager?.unregisterListener(this)
    }

    @Synchronized
    override fun onSensorChanged(event: SensorEvent) {
        val magnitude = sqrt(
            event.values[0] * event.values[0].toDouble() +
                event.values[1] * event.values[1].toDouble() +
                event.values[2] * event.values[2].toDouble(),
        )
        val gravity =
            if (event.sensor.type == Sensor.TYPE_LINEAR_ACCELERATION) 0.0 else GRAVITY_MPS2
        val deviation = abs(magnitude - gravity) / GRAVITY_MPS2
        val now = System.currentTimeMillis()
        if (deviation > ACTIVE_THRESHOLD_G) {
            if (activeWindowStartedMillis == 0L) {
                activeWindowStartedMillis = now
            }
        } else if (activeWindowStartedMillis != 0L) {
            activeSeconds += (now - activeWindowStartedMillis) / 1000.0
            activeWindowStartedMillis = 0L
        }
        sumDeviation += deviation
        if (deviation > maxDeviation) maxDeviation = deviation
        sampleCount++
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /** Snapshot and reset the current window's aggregates. */
    @Synchronized
    fun snapshotAndReset(): Map<String, Double> {
        val now = System.currentTimeMillis()
        if (activeWindowStartedMillis != 0L) {
            activeSeconds += (now - activeWindowStartedMillis) / 1000.0
            activeWindowStartedMillis = 0L
        }
        if (sampleCount == 0L) return emptyMap()
        val result = mapOf(
            "motion_active_seconds" to activeSeconds,
            "motion_mean_deviation_g" to (sumDeviation / sampleCount),
            "motion_max_deviation_g" to maxDeviation,
        )
        activeSeconds = 0.0
        sumDeviation = 0.0
        maxDeviation = 0.0
        sampleCount = 0L
        return result
    }
}
