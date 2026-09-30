package com.workoutnotes.workout_notes.medication

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MedicationReminderPolicyTest {
    private val zone = TimeZone.getTimeZone("America/Sao_Paulo")

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(year, month - 1, day, hour, minute, 0)
        }.timeInMillis

    @Test
    fun `next occurrence is later today when the time has not passed`() {
        // Tuesday 2026-09-29 07:00.
        val now = at(2026, 9, 29, 7, 0)
        val next = MedicationReminderPolicy.nextOccurrence(8, 0, emptySet(), now, zone)
        assertEquals(at(2026, 9, 29, 8, 0), next)
    }

    @Test
    fun `next occurrence moves to tomorrow once the time passed`() {
        val now = at(2026, 9, 29, 8, 0)
        val next = MedicationReminderPolicy.nextOccurrence(8, 0, emptySet(), now, zone)
        assertEquals(at(2026, 9, 30, 8, 0), next)
    }

    @Test
    fun `next occurrence honours the selected weekdays`() {
        // Tuesday evening; only Mondays (1) and Fridays (5) are selected.
        val now = at(2026, 9, 29, 21, 0)
        val next = MedicationReminderPolicy.nextOccurrence(9, 30, setOf(1, 5), now, zone)
        assertEquals(at(2026, 10, 2, 9, 30), next)
    }

    @Test
    fun `dose key uses local date and time`() {
        assertEquals(
            "2026-09-29T08:05",
            MedicationReminderPolicy.doseKey(at(2026, 9, 29, 8, 5), zone),
        )
    }

    @Test
    fun `reminder is skipped for a dose already confirmed`() {
        val key = "2026-09-29T08:00"
        assertFalse(MedicationReminderPolicy.shouldRemind(key, setOf(key)))
        assertTrue(MedicationReminderPolicy.shouldRemind(key, emptySet()))
    }

    @Test
    fun `escalation rings only for the pending unconfirmed dose`() {
        val key = "2026-09-29T08:00"
        assertTrue(
            MedicationReminderPolicy.shouldEscalate(
                MedicationReminderPolicy.STATE_AWAITING, key, key, emptySet(),
            ),
        )
        // Confirmed in the meantime.
        assertFalse(
            MedicationReminderPolicy.shouldEscalate(
                MedicationReminderPolicy.STATE_AWAITING, key, key, setOf(key),
            ),
        )
        // A stale escalation for an older dose.
        assertFalse(
            MedicationReminderPolicy.shouldEscalate(
                MedicationReminderPolicy.STATE_AWAITING, key, "2026-09-28T08:00", emptySet(),
            ),
        )
        assertFalse(
            MedicationReminderPolicy.shouldEscalate(
                MedicationReminderPolicy.STATE_SCHEDULED, key, key, emptySet(),
            ),
        )
    }

    @Test
    fun `escalation delay is clamped`() {
        assertEquals(60_000L, MedicationReminderPolicy.escalationDelayMillis(0))
        assertEquals(30 * 60_000L, MedicationReminderPolicy.escalationDelayMillis(30))
    }

    @Test
    fun `confirmed keys keep only the most recent entries`() {
        val keys = (1..50).map { "2026-09-%02dT08:00".format(it % 28 + 1) + it }.toSet()
        assertEquals(40, MedicationReminderPolicy.pruneConfirmed(keys).size)
    }
}
