package com.workoutnotes.workout_notes.run

import org.junit.Assert.assertEquals
import org.junit.Test

class RunTrackingNotificationTest {
    @Test
    fun formatsDurationAndPace() {
        assertEquals("05:07", RunTrackingNotification.formatDuration(307))
        assertEquals("1:02:03", RunTrackingNotification.formatDuration(3723))
        assertEquals("5:32 /km", RunTrackingNotification.formatPace(332.0))
        assertEquals("--:-- /km", RunTrackingNotification.formatPace(null))
        assertEquals("--:-- /km", RunTrackingNotification.formatPace(0.0))
    }

    @Test
    fun summaryShowsTimeDistanceAndPace() {
        assertEquals(
            "12:34 · 2,35 km · 5:20 /km",
            RunTrackingNotification.summaryText(2350.0, 754, 320.0, portuguese = true),
        )
        assertEquals(
            "12:34 · 2.35 km · 5:20 /km",
            RunTrackingNotification.summaryText(2350.0, 754, 320.0, portuguese = false),
        )
    }
}
