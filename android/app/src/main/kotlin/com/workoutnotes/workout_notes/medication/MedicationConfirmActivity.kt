package com.workoutnotes.workout_notes.medication

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.workoutnotes.workout_notes.R

/**
 * Confirmation screen for one medication dose. Opened by tapping the reminder
 * notification or by the escalation alarm (full screen, over the lock screen).
 * While the alarm rings the screen cannot be dismissed without an answer.
 */
class MedicationConfirmActivity : Activity() {
    private var slotId: String? = null
    private var doseKey: String? = null

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        showOverLockScreen()
        readIntent(intent)
        render()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readIntent(intent)
        render()
    }

    @Deprecated("Deprecated in Android SDK")
    override fun onBackPressed() {
        val slot = slotId?.let { MedicationReminderScheduler.read(this, it) }
        if (slot?.state == MedicationReminderPolicy.STATE_RINGING) return
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    private fun readIntent(intent: Intent) {
        slotId = intent.getStringExtra(MedicationReminderScheduler.EXTRA_SLOT_ID)
        doseKey = intent.getStringExtra(MedicationReminderScheduler.EXTRA_DOSE_KEY)
    }

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun render() {
        val id = slotId ?: run { finish(); return }
        val slot = MedicationReminderScheduler.read(this, id) ?: run { finish(); return }
        val key = doseKey ?: slot.pendingDoseKey
        val ringing = slot.state == MedicationReminderPolicy.STATE_RINGING
        val alreadyLogged = key == null || slot.confirmedKeys.contains(key)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(64), dp(28), dp(32))
            setBackgroundColor(Color.rgb(16, 24, 30))
        }
        root.addView(
            TextView(this).apply {
                text = "💊"
                textSize = 56f
                gravity = Gravity.CENTER
            },
        )
        root.addView(
            label(
                getString(if (ringing) R.string.medication_alarm_title else R.string.medication_reminder_title),
                15f,
                Color.rgb(128, 203, 196),
                bold = true,
            ).apply { setPadding(0, dp(12), 0, 0) },
        )
        root.addView(label(slot.name, 30f, Color.WHITE, bold = true).apply { setPadding(0, dp(6), 0, 0) })
        if (!slot.dosage.isNullOrBlank()) {
            root.addView(label(slot.dosage, 18f, Color.rgb(200, 210, 215)))
        }
        root.addView(
            label(
                getString(
                    R.string.medication_dose_time,
                    String.format(java.util.Locale.US, "%02d:%02d", slot.hour, slot.minute),
                ),
                16f,
                Color.rgb(160, 172, 180),
            ).apply { setPadding(0, dp(18), 0, 0) },
        )
        root.addView(
            label(
                getString(
                    when {
                        alreadyLogged -> R.string.medication_already_logged
                        ringing -> R.string.medication_alarm_body
                        else -> R.string.medication_confirm_body
                    },
                ),
                15f,
                Color.rgb(160, 172, 180),
            ).apply { setPadding(0, dp(8), 0, 0) },
        )
        root.addView(TextView(this), LinearLayout.LayoutParams(1, 0, 1f))

        if (!alreadyLogged) {
            root.addView(
                button(getString(R.string.medication_taken), filled = true) {
                    answer(id, key!!, MedicationReminderScheduler.STATUS_TAKEN)
                },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(58)),
            )
            root.addView(
                button(getString(R.string.medication_skip), filled = false) {
                    answer(id, key!!, MedicationReminderScheduler.STATUS_SKIPPED)
                },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(54)).apply {
                    topMargin = dp(12)
                },
            )
        }
        if (!ringing || alreadyLogged) {
            root.addView(
                button(getString(R.string.medication_not_now), filled = false, subtle = true) {
                    finishAndRemoveTask()
                },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)).apply {
                    topMargin = dp(8)
                },
            )
        }
        setContentView(root)
    }

    private fun answer(id: String, key: String, status: String) {
        MedicationReminderScheduler.confirm(this, id, key, status, fromNative = true)
        finishAndRemoveTask()
    }

    private fun label(value: String, size: Float, color: Int, bold: Boolean = false) =
        TextView(this).apply {
            text = value
            textSize = size
            gravity = Gravity.CENTER
            setTextColor(color)
            if (bold) setTypeface(typeface, Typeface.BOLD)
        }

    private fun button(value: String, filled: Boolean, subtle: Boolean = false, onClick: () -> Unit) =
        Button(this).apply {
            text = value
            textSize = 16f
            isAllCaps = false
            setTypeface(typeface, Typeface.BOLD)
            val accent = MedicationNotifications.ACCENT
            setTextColor(
                when {
                    filled -> Color.WHITE
                    subtle -> Color.rgb(160, 172, 180)
                    else -> Color.rgb(128, 203, 196)
                },
            )
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                if (filled) {
                    setColor(accent)
                } else if (!subtle) {
                    setColor(Color.TRANSPARENT)
                    setStroke(dp(1), Color.rgb(70, 110, 105))
                } else {
                    setColor(Color.TRANSPARENT)
                }
            }
            setOnClickListener { onClick() }
        }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
