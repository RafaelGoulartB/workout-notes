package com.workoutnotes.workout_notes.sleep

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.os.Handler
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.content.ContextCompat

/**
 * Pure time-accounting core for bedside phone interaction and motion triggers.
 *
 * Tracks exact durations inside each 30-second window without polling:
 * - [screenOnSeconds]: time the display was interactive (includes lockscreen).
 * - [deviceActiveSeconds]: time the display was interactive AND unlocked (when
 *   no secure keyguard is configured and `ACTION_USER_PRESENT` was not seen,
 *   requires continuous screen-on past [unsecuredWakeGraceMillis] so a 5–10 s
 *   notification wake does not read as active phone use).
 * - [phonePickupCount]: hardware `TYPE_SIGNIFICANT_MOTION` triggers (gross
 *   phone movement / getting up with the phone; gentle nightstand lifts may
 *   not trigger it).
 *
 * Kept independent of Android framework types so every state transition can be
 * tested directly on the JVM.
 */
internal class DeviceActivityWindow(
    initialElapsedMillis: Long,
    initialInteractive: Boolean,
    initialUnlocked: Boolean,
    initialUserPresent: Boolean = initialUnlocked,
    private val unsecuredWakeGraceMillis: Long = DEFAULT_UNSECURED_WAKE_GRACE_MILLIS,
) {
    companion object {
        const val DEFAULT_UNSECURED_WAKE_GRACE_MILLIS = 12_000L
    }

    private var lastElapsedMillis = initialElapsedMillis
    private var interactive = initialInteractive
    private var unlocked = initialInteractive && initialUnlocked
    private var sawLockedSinceScreenOn = initialInteractive && !initialUnlocked
    private var userPresentConfirmed = initialInteractive && initialUnlocked && initialUserPresent
    private var interactiveSinceMillis = if (initialInteractive) initialElapsedMillis else -1L
    private var screenOnMillis = 0L
    private var deviceActiveMillis = 0L
    private var pickupCount = 0

    @Synchronized
    fun onStateChange(
        elapsedMillis: Long,
        isInteractive: Boolean,
        isUnlocked: Boolean,
        userPresent: Boolean = false,
    ) {
        accumulateUntil(elapsedMillis)
        if (!isInteractive) {
            interactive = false
            unlocked = false
            sawLockedSinceScreenOn = false
            userPresentConfirmed = false
            interactiveSinceMillis = -1L
        } else {
            if (!interactive) {
                interactiveSinceMillis = elapsedMillis
                sawLockedSinceScreenOn = !isUnlocked
            } else if (!isUnlocked) {
                sawLockedSinceScreenOn = true
            }
            interactive = true
            unlocked = isUnlocked
            // Only confirm immediate presence when USER_PRESENT follows an
            // observed locked state; when lockscreen is "None" (or within a
            // lock-after-timeout grace), AOSP may broadcast USER_PRESENT on
            // notification wakes, so keep the 12 s continuous-on grace.
            if (userPresent && isUnlocked && sawLockedSinceScreenOn) {
                userPresentConfirmed = true
            }
            if (!isUnlocked) userPresentConfirmed = false
        }
    }

    @Synchronized
    fun onPickup(elapsedMillis: Long) {
        accumulateUntil(elapsedMillis)
        pickupCount++
    }

    /**
     * Closes the current window using broadcast-tracked state (zero Binder
     * IPCs). When [fallbackInteractive]/[fallbackUnlocked] are provided (only
     * if receiver registration failed), refreshes state if time did not go
     * backward.
     */
    @Synchronized
    fun snapshot(
        elapsedMillis: Long,
        fallbackInteractive: Boolean? = null,
        fallbackUnlocked: Boolean? = null,
    ): Map<String, Any?> {
        accumulateUntil(elapsedMillis)
        val screenSeconds = screenOnMillis / 1_000.0
        val activeSeconds = deviceActiveMillis / 1_000.0
        val pickups = pickupCount
        screenOnMillis = 0L
        deviceActiveMillis = 0L
        pickupCount = 0
        if (fallbackInteractive != null &&
            fallbackUnlocked != null &&
            elapsedMillis >= lastElapsedMillis
        ) {
            if (!fallbackInteractive) {
                interactive = false
                unlocked = false
                sawLockedSinceScreenOn = false
                userPresentConfirmed = false
                interactiveSinceMillis = -1L
            } else {
                if (!interactive) {
                    interactiveSinceMillis = elapsedMillis
                    sawLockedSinceScreenOn = !fallbackUnlocked
                } else if (!fallbackUnlocked) {
                    sawLockedSinceScreenOn = true
                }
                interactive = true
                unlocked = fallbackUnlocked
                if (!fallbackUnlocked) userPresentConfirmed = false
            }
        }
        return mapOf(
            "screen_on_seconds" to screenSeconds,
            "device_active_seconds" to activeSeconds,
            "phone_pickup_count" to pickups,
        )
    }

    private fun accumulateUntil(elapsedMillis: Long) {
        val delta = elapsedMillis - lastElapsedMillis
        if (delta <= 0L) return
        if (interactive) {
            screenOnMillis += delta
            if (unlocked) {
                if (userPresentConfirmed || unsecuredWakeGraceMillis <= 0L) {
                    deviceActiveMillis += delta
                } else {
                    val graceEndsAt = interactiveSinceMillis + unsecuredWakeGraceMillis
                    val activeStart = maxOf(lastElapsedMillis, graceEndsAt)
                    if (elapsedMillis > activeStart) {
                        deviceActiveMillis += elapsedMillis - activeStart
                    }
                }
            }
        }
        lastElapsedMillis = elapsedMillis
    }
}

/**
 * Event-driven bedside device activity tracker.
 *
 * Listens to OS screen/unlock broadcasts (`ACTION_SCREEN_ON`,
 * `ACTION_SCREEN_OFF`, `ACTION_USER_PRESENT`) and the hardware one-shot
 * `Sensor.TYPE_SIGNIFICANT_MOTION` trigger (which runs on the sensor hub with
 * negligible battery cost on a nightstand; note that it targets gross movement
 * such as walking or vigorous handling rather than gentle lifts). When the
 * broadcast receiver is registered, [snapshot] makes zero Binder calls.
 * Requires no additional Android permissions.
 */
internal class SleepDeviceActivityTracker(
    private val context: Context,
    private val mainHandler: Handler,
) {
    companion object {
        private const val PICKUP_REARM_DELAY_MILLIS = 10_000L
    }

    private val powerManager =
        context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    private val keyguardManager =
        context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val significantMotion =
        sensorManager?.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)

    private val lock = Any()
    private val initialInteractive = readInteractive()
    private val initialUnlocked = initialInteractive && readNotKeyguardLocked()
    private val window = DeviceActivityWindow(
        initialElapsedMillis = SystemClock.elapsedRealtime(),
        initialInteractive = initialInteractive,
        initialUnlocked = initialUnlocked,
        initialUserPresent = initialUnlocked,
    )

    private var started = false
    private var receiverRegistered = false
    private var motionArmed = false

    private val rearmMotion = Runnable {
        synchronized(lock) {
            if (started) armSignificantMotionLocked()
        }
    }

    private val triggerListener = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent?) {
            synchronized(lock) {
                motionArmed = false
                if (!started) return
                window.onPickup(SystemClock.elapsedRealtime())
                mainHandler.removeCallbacks(rearmMotion)
                mainHandler.postDelayed(rearmMotion, PICKUP_REARM_DELAY_MILLIS)
            }
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            synchronized(lock) {
                if (!started) return
                when (action) {
                    Intent.ACTION_SCREEN_OFF, Intent.ACTION_DREAMING_STARTED -> window.onStateChange(
                        SystemClock.elapsedRealtime(),
                        isInteractive = false,
                        isUnlocked = false,
                        userPresent = false,
                    )
                    Intent.ACTION_USER_PRESENT -> {
                        // Guard against a stale USER_PRESENT arriving after
                        // SCREEN_OFF; presence is confirmed inside the window
                        // only when a locked keyguard was seen since SCREEN_ON.
                        if (readInteractive()) {
                            window.onStateChange(
                                SystemClock.elapsedRealtime(),
                                isInteractive = true,
                                isUnlocked = true,
                                userPresent = true,
                            )
                        }
                    }
                    Intent.ACTION_SCREEN_ON, Intent.ACTION_DREAMING_STOPPED -> {
                        val interactive = action == Intent.ACTION_SCREEN_ON || readInteractive()
                        val unlocked = interactive && readNotKeyguardLocked()
                        // Never confirm userPresent on bare SCREEN_ON: both a
                        // "None" lockscreen and a secure lockscreen still
                        // inside its lock-after-timeout delay report unlocked
                        // on notification wakes, so wait for either a real
                        // unlock (USER_PRESENT after locked) or the 12 s grace.
                        // Note: fast screen-off biometric unlock that clears
                        // keyguard before SCREEN_ON runs also incurs the 12 s
                        // grace (safe under-counting of brief glances).
                        window.onStateChange(
                            SystemClock.elapsedRealtime(),
                            isInteractive = interactive,
                            isUnlocked = unlocked,
                            userPresent = false,
                        )
                    }
                }
            }
        }
    }

    fun start() {
        synchronized(lock) {
            if (started) return
            started = true
            val interactive = readInteractive()
            val unlocked = interactive && readNotKeyguardLocked()
            window.onStateChange(
                SystemClock.elapsedRealtime(),
                isInteractive = interactive,
                isUnlocked = unlocked,
                userPresent = unlocked,
            )
            try {
                val filter = IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_SCREEN_OFF)
                    addAction(Intent.ACTION_USER_PRESENT)
                    addAction(Intent.ACTION_DREAMING_STARTED)
                    addAction(Intent.ACTION_DREAMING_STOPPED)
                }
                ContextCompat.registerReceiver(
                    context,
                    screenReceiver,
                    filter,
                    ContextCompat.RECEIVER_NOT_EXPORTED,
                )
                receiverRegistered = true
            } catch (_: Throwable) {
                // Fall back to snapshot-time PowerManager/KeyguardManager reads.
                receiverRegistered = false
            }
            armSignificantMotionLocked()
        }
    }

    fun snapshot(): Map<String, Any?> {
        val useFallback = synchronized(lock) { !receiverRegistered }
        return if (useFallback) {
            val interactive = readInteractive()
            val unlocked = interactive && readNotKeyguardLocked()
            window.snapshot(
                elapsedMillis = SystemClock.elapsedRealtime(),
                fallbackInteractive = interactive,
                fallbackUnlocked = unlocked,
            )
        } else {
            // BroadcastReceiver keeps state current: zero Binder IPCs per 30 s.
            window.snapshot(elapsedMillis = SystemClock.elapsedRealtime())
        }
    }

    fun stop() {
        synchronized(lock) {
            if (!started) return
            started = false
            mainHandler.removeCallbacks(rearmMotion)
            if (motionArmed) {
                try {
                    significantMotion?.let { sensorManager?.cancelTriggerSensor(triggerListener, it) }
                } catch (_: Throwable) {
                    // Best-effort sensor cancellation during teardown.
                }
                motionArmed = false
            }
            if (receiverRegistered) {
                try {
                    context.unregisterReceiver(screenReceiver)
                } catch (_: Throwable) {
                    // Already unregistered during teardown.
                }
                receiverRegistered = false
            }
        }
    }

    private fun armSignificantMotionLocked() {
        val sensor = significantMotion ?: return
        if (motionArmed || !started) return
        try {
            motionArmed = sensorManager?.requestTriggerSensor(triggerListener, sensor) == true
        } catch (_: Throwable) {
            motionArmed = false
        }
    }

    private fun readInteractive(): Boolean = try {
        powerManager?.isInteractive == true
    } catch (_: Throwable) {
        false
    }

    private fun readNotKeyguardLocked(): Boolean = try {
        keyguardManager?.isKeyguardLocked == false
    } catch (_: Throwable) {
        false
    }
}
