package com.workoutnotes.workout_notes.medication

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MedicationReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val id = intent?.getStringExtra(MedicationReminderScheduler.EXTRA_SLOT_ID) ?: return
        when (intent.action) {
            MedicationReminderScheduler.ACTION_REMIND -> MedicationReminderScheduler.onReminder(
                context,
                id,
                intent.getLongExtra(MedicationReminderScheduler.EXTRA_DUE_AT, 0L),
            )
            MedicationReminderScheduler.ACTION_ESCALATE -> MedicationReminderScheduler.onEscalate(
                context,
                id,
                intent.getStringExtra(MedicationReminderScheduler.EXTRA_DOSE_KEY),
            )
        }
    }
}
