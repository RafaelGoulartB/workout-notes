package com.workoutnotes.workout_notes.sleep

import org.junit.Assert.assertEquals
import org.junit.Test

class SleepDeviceActivityTrackerTest {
    @Test
    fun lockscreenNotificationDoesNotCountAsUnlockedDeviceUse() {
        val window = DeviceActivityWindow(
            initialElapsedMillis = 0L,
            initialInteractive = false,
            initialUnlocked = false,
        )
        // Notification wakes lockscreen for 6 seconds, then screen turns off.
        window.onStateChange(5_000L, isInteractive = true, isUnlocked = false)
        window.onStateChange(11_000L, isInteractive = false, isUnlocked = false)

        val snap = window.snapshot(30_000L)
        assertEquals(6.0, snap["screen_on_seconds"] as Double, 1e-6)
        assertEquals(0.0, snap["device_active_seconds"] as Double, 1e-6)
        assertEquals(0, snap["phone_pickup_count"])
    }

    @Test
    fun unsecuredNotificationWakeWithinGraceDoesNotCountAsActiveUse() {
        val window = DeviceActivityWindow(
            initialElapsedMillis = 0L,
            initialInteractive = false,
            initialUnlocked = false,
            unsecuredWakeGraceMillis = 12_000L,
        )
        // Lockscreen set to "None": notification lights screen for 8 s; even if
        // AOSP sends ACTION_USER_PRESENT on wake, no locked keyguard was seen,
        // so the 12 s grace still filters out the notification.
        window.onStateChange(5_000L, isInteractive = true, isUnlocked = true, userPresent = false)
        window.onStateChange(5_100L, isInteractive = true, isUnlocked = true, userPresent = true)
        window.onStateChange(13_000L, isInteractive = false, isUnlocked = false)
        val notif = window.snapshot(30_000L)
        assertEquals(8.0, notif["screen_on_seconds"] as Double, 1e-6)
        assertEquals(0.0, notif["device_active_seconds"] as Double, 1e-6)

        // Real phone reading without keyguard stays on 25 s: 13 s past 12 s grace.
        window.onStateChange(35_000L, isInteractive = true, isUnlocked = true, userPresent = false)
        window.onStateChange(35_100L, isInteractive = true, isUnlocked = true, userPresent = true)
        val reading = window.snapshot(60_000L)
        assertEquals(25.0, reading["screen_on_seconds"] as Double, 1e-6)
        assertEquals(13.0, reading["device_active_seconds"] as Double, 1e-6)
    }

    @Test
    fun dreamingWhileChargingStopsDeviceActiveAccounting() {
        val window = DeviceActivityWindow(
            initialElapsedMillis = 0L,
            initialInteractive = true,
            initialUnlocked = true,
            initialUserPresent = true,
        )
        // Screen saver (dream) starts at 10 s while charging.
        window.onStateChange(10_000L, isInteractive = false, isUnlocked = false)
        val first = window.snapshot(30_000L)
        assertEquals(10.0, first["device_active_seconds"] as Double, 1e-6)
        val second = window.snapshot(60_000L)
        assertEquals(0.0, second["device_active_seconds"] as Double, 1e-6)
    }

    @Test
    fun unlockAndCarryOverAcrossWindowBoundariesAreAccountedExactly() {
        val window = DeviceActivityWindow(
            initialElapsedMillis = 0L,
            initialInteractive = false,
            initialUnlocked = false,
        )
        // User moves phone at 10 s, wakes lockscreen at 10 s, unlocks at 12 s,
        // keeps using it past the 30 s boundary until 45 s.
        window.onPickup(10_000L)
        window.onStateChange(10_000L, isInteractive = true, isUnlocked = false)
        window.onStateChange(12_000L, isInteractive = true, isUnlocked = true, userPresent = true)

        val first = window.snapshot(30_000L)
        assertEquals(20.0, first["screen_on_seconds"] as Double, 1e-6)
        assertEquals(18.0, first["device_active_seconds"] as Double, 1e-6)
        assertEquals(1, first["phone_pickup_count"])

        // Next window starts unlocked, user locks at 45 s.
        window.onStateChange(45_000L, isInteractive = false, isUnlocked = false)
        val second = window.snapshot(60_000L)
        assertEquals(15.0, second["screen_on_seconds"] as Double, 1e-6)
        assertEquals(15.0, second["device_active_seconds"] as Double, 1e-6)
        assertEquals(0, second["phone_pickup_count"])

        // Quiet third window resets to zero.
        val third = window.snapshot(90_000L)
        assertEquals(0.0, third["screen_on_seconds"] as Double, 1e-6)
        assertEquals(0.0, third["device_active_seconds"] as Double, 1e-6)
        assertEquals(0, third["phone_pickup_count"])
    }

    @Test
    fun staleFallbackSnapshotCannotClobberNewerBroadcastState() {
        val window = DeviceActivityWindow(
            initialElapsedMillis = 0L,
            initialInteractive = false,
            initialUnlocked = false,
        )
        window.onStateChange(30_040L, isInteractive = true, isUnlocked = false)
        window.onStateChange(30_050L, isInteractive = true, isUnlocked = true, userPresent = true)
        // Snapshot timestamp precedes the newer broadcast: must not overwrite live true state.
        window.snapshot(30_000L, fallbackInteractive = false, fallbackUnlocked = false)
        val next = window.snapshot(60_050L)
        assertEquals(30.0, next["device_active_seconds"] as Double, 1e-6)
    }
}
