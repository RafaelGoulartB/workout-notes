package com.workoutnotes.workout_notes.medication

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import androidx.core.app.NotificationCompat
import com.workoutnotes.workout_notes.R
import com.workoutnotes.workout_notes.common.PendingIntentFlags
import com.workoutnotes.workout_notes.common.NotificationChannels
import com.workoutnotes.workout_notes.common.NotificationChannels.silent

/** Channels and the reminder notification for medication doses. */
object MedicationNotifications {
    const val REMINDER_CHANNEL = "medication_reminder"
    const val ALARM_CHANNEL = "medication_alarm"
    val ACCENT: Int = Color.rgb(46, 125, 110)

    fun ensureChannels(context: Context) {
        NotificationChannels.ensure(
            context,
            REMINDER_CHANNEL,
            context.getString(R.string.medication_reminder_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ) {
            description = context.getString(R.string.medication_reminder_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
        }
        NotificationChannels.ensure(
            context,
            ALARM_CHANNEL,
            context.getString(R.string.medication_alarm_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ) {
            description = context.getString(R.string.medication_alarm_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            // The ringing service plays the alarm sound itself.
            silent()
        }
    }

    /** Tapping the reminder opens the confirmation screen for that dose. */
    fun showReminder(context: Context, slot: MedicationReminderScheduler.Slot) {
        ensureChannels(context)
        val notification = NotificationCompat.Builder(context, REMINDER_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setColor(ACCENT)
            .setContentTitle(reminderTitle(context, slot))
            .setContentText(doseLabel(slot))
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "${doseLabel(slot)}\n" +
                        context.getString(R.string.medication_reminder_confirm_hint),
                ),
            )
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .setOngoing(false)
            .setContentIntent(confirmIntent(context, slot, slot.pendingDoseKey))
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(MedicationReminderScheduler.notificationId(slot.id), notification)
    }

    fun confirmIntent(
        context: Context,
        slot: MedicationReminderScheduler.Slot,
        doseKey: String?,
    ): PendingIntent = PendingIntent.getActivity(
        context,
        MedicationReminderScheduler.notificationId(slot.id),
        Intent(context, MedicationConfirmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MedicationReminderScheduler.EXTRA_SLOT_ID, slot.id)
            putExtra(MedicationReminderScheduler.EXTRA_DOSE_KEY, doseKey)
        },
        PendingIntentFlags.UPDATE_IMMUTABLE,
    )

    /**
     * "Time for your medication", or "Missed dose from 08:00" for a dose
     * reminded late after the phone was off.
     */
    private fun reminderTitle(context: Context, slot: MedicationReminderScheduler.Slot): String {
        val late = slot.pendingDueAt > 0L &&
            System.currentTimeMillis() - slot.pendingDueAt > LATE_AFTER_MILLIS
        if (!late) return context.getString(R.string.medication_reminder_title)
        val time = android.text.format.DateFormat.getTimeFormat(context)
            .format(java.util.Date(slot.pendingDueAt))
        return context.getString(R.string.medication_reminder_late_title, time)
    }

    private const val LATE_AFTER_MILLIS = 5L * 60_000L

    fun doseLabel(slot: MedicationReminderScheduler.Slot): String =
        if (slot.dosage.isNullOrBlank()) slot.name else "${slot.name} · ${slot.dosage}"
}
