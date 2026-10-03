package com.workoutnotes.workout_notes.common

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class AlarmTimePolicyTest {
    private val saoPaulo = TimeZone.getTimeZone("America/Sao_Paulo")
    private val lisbon = TimeZone.getTimeZone("Europe/Lisbon")

    private fun at(zone: TimeZone, year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(year, month - 1, day, hour, minute, 0)
        }.timeInMillis

    @Test
    fun `a 07 00 alarm follows the traveller to local 07 00`() {
        // Armed in Sao Paulo (UTC-3) for tomorrow 07:00 there; the phone lands in Lisbon.
        val armed = at(saoPaulo, 2026, 7, 2, 7, 0)
        val now = at(lisbon, 2026, 7, 1, 23, 30)
        val refreshed = AlarmTimePolicy.refreshedAt(
            armed, now, hour = 7, minute = 0, weekdays = emptySet(), snoozed = false, timeZone = lisbon,
        )
        assertEquals(at(lisbon, 2026, 7, 2, 7, 0), refreshed)
    }

    @Test
    fun `the weekdays are read in the new time zone`() {
        // Mondays only (1). Friday night in Lisbon: the next one is Monday 07:00 local.
        val now = at(lisbon, 2026, 7, 3, 22, 0)
        val refreshed = AlarmTimePolicy.refreshedAt(
            now + 3_600_000L, now, 7, 0, setOf(1), snoozed = false, timeZone = lisbon,
        )
        assertEquals(at(lisbon, 2026, 7, 6, 7, 0), refreshed)
    }

    @Test
    fun `a snoozed alarm keeps its instant`() {
        val now = at(lisbon, 2026, 7, 2, 7, 0)
        val snoozedUntil = now + 5 * 60_000L
        val refreshed = AlarmTimePolicy.refreshedAt(
            snoozedUntil, now, 7, 0, emptySet(), snoozed = true, timeZone = lisbon,
        )
        assertEquals(snoozedUntil, refreshed)
    }

    @Test
    fun `an alarm already due is left to the system`() {
        val now = at(lisbon, 2026, 7, 2, 8, 0)
        val due = now - 60_000L
        val refreshed = AlarmTimePolicy.refreshedAt(
            due, now, 7, 59, emptySet(), snoozed = false, timeZone = lisbon,
        )
        assertEquals(due, refreshed)
    }

    @Test
    fun `an unchanged zone gives the same instant`() {
        val now = at(saoPaulo, 2026, 7, 1, 22, 0)
        val armed = at(saoPaulo, 2026, 7, 2, 7, 0)
        val refreshed = AlarmTimePolicy.refreshedAt(
            armed, now, 7, 0, emptySet(), snoozed = false, timeZone = saoPaulo,
        )
        assertEquals(armed, refreshed)
    }
}
