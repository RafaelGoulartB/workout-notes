package com.workoutnotes.workout_notes.sleep

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.Chronometer
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextClock
import android.widget.TextView
import com.workoutnotes.workout_notes.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Wake-up screen of a monitored night. While ringing it offers snooze and the
 * way to turn the alarm off (the mission, when there is one). During a snooze
 * it opens silently from the snooze notification or the app, so the mission
 * can be completed early; leaving keeps the snooze as it was.
 */
class SleepAlarmActivity : Activity() {
    private var missionError: String? = null
    private var showCameraSettings = false
    private var pulse: AnimatorSet? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SleepAlarmUi.configureWindow(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // onResume follows and renders the new state (e.g. the snooze rang).
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    override fun onPause() {
        pulse?.cancel()
        pulse = null
        super.onPause()
    }

    @Deprecated("Deprecated in Android SDK")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SCAN_REQUEST) return
        if (resultCode != BarcodeScannerActivity.RESULT_SUCCESS || data == null) {
            SleepAlarmRingingService.resumeAfterBarcode(this)
            if (data?.getBooleanExtra(BarcodeScannerActivity.EXTRA_CAMERA_DENIED, false) == true) {
                missionError = getString(R.string.sleep_alarm_mission_camera_denied)
                showCameraSettings = true
            } else if (data?.getBooleanExtra(BarcodeScannerActivity.EXTRA_TIMEOUT, false) == true) {
                missionError = getString(R.string.sleep_alarm_mission_timeout)
            }
            return
        }
        val raw = data.getStringExtra(BarcodeScannerActivity.EXTRA_RAW_VALUE)
        val format = data.getStringExtra(BarcodeScannerActivity.EXTRA_FORMAT)
        if (raw != null && format != null &&
            SleepAlarmRingingService.completeBarcode(this, raw, format)
        ) {
            finishAndRemoveTask()
        } else {
            SleepAlarmRingingService.resumeAfterBarcode(this)
            missionError = getString(R.string.sleep_alarm_mission_wrong_code)
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // A ringing alarm must be explicitly handled; a snooze just continues.
        if (SleepAlarmScheduler.read(this)?.isSnoozed == true) super.onBackPressed()
    }

    private fun render() {
        pulse?.cancel()
        pulse = null
        val snapshot = SleepAlarmScheduler.read(this)
        val ringing = snapshot?.state == SleepAlarmScheduler.STATE_RINGING
        if (snapshot == null || (!ringing && !snapshot.isSnoozed)) {
            // Already turned off (here, in the app or from the notification).
            finishAndRemoveTask()
            return
        }
        val mission = snapshot.requiresMission

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(40), dp(28), dp(28))
            background = SleepAlarmUi.background(ringing)
        }
        root.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        root.addView(halo(ringing), LinearLayout.LayoutParams(dp(150), dp(150)))

        root.addView(TextView(this).apply {
            text = getString(
                if (ringing) R.string.sleep_alarm_good_morning else R.string.sleep_alarm_snoozed_label,
            )
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(SleepAlarmUi.muted)
        }, wrap(top = 8))

        root.addView(bigTime(ringing, snapshot.alarmAtMillis), wrap())

        root.addView(
            if (ringing) {
                TextView(this).apply {
                    text = longDate()
                    textSize = 16f
                    gravity = Gravity.CENTER
                    setTextColor(SleepAlarmUi.muted)
                }
            } else {
                Chronometer(this).apply {
                    base = SystemClock.elapsedRealtime() +
                        (snapshot.alarmAtMillis - System.currentTimeMillis())
                    isCountDown = true
                    format = getString(R.string.sleep_alarm_rings_again_in)
                    textSize = 16f
                    gravity = Gravity.CENTER
                    setTextColor(SleepAlarmUi.muted)
                    start()
                }
            },
            wrap(),
        )

        root.addView(TextView(this).apply {
            text = getString(
                when {
                    mission && ringing -> R.string.sleep_alarm_mission_body
                    mission -> R.string.sleep_alarm_snoozed_mission_body
                    ringing -> R.string.sleep_alarm_wake_message
                    else -> R.string.sleep_alarm_snoozed_dismiss_body
                },
            )
            textSize = 15f
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.15f)
            setTextColor(SleepAlarmUi.muted)
        }, wrap(top = 28))

        val error = missionError
        if (mission && error != null) {
            root.addView(TextView(this).apply {
                text = error
                textSize = 15f
                gravity = Gravity.CENTER
                setTextColor(SleepAlarmUi.error)
            }, wrap(top = 12))
            if (showCameraSettings) {
                root.addView(
                    SleepAlarmUi.textButton(this, getString(R.string.sleep_alarm_open_camera_settings)) {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName"),
                            ),
                        )
                    },
                    wrap(),
                )
            }
        }

        root.addView(View(this), LinearLayout.LayoutParams(1, 0, 1.3f))

        if (ringing && SleepAlarmScheduler.canSnooze(this)) {
            val left = snapshot.maxSnoozes - snapshot.snoozeCount
            root.addView(
                SleepAlarmUi.pillButton(
                    this,
                    getString(R.string.sleep_alarm_snooze_left, left),
                    filled = false,
                ) {
                    SleepAlarmRingingService.snooze(this)
                    finishAndRemoveTask()
                },
                button(),
            )
        }
        root.addView(
            SleepAlarmUi.pillButton(
                this,
                getString(
                    when {
                        mission -> R.string.sleep_alarm_scan_code
                        ringing -> R.string.sleep_alarm_dismiss
                        else -> R.string.sleep_alarm_dismiss_now
                    },
                ),
                filled = true,
            ) {
                when {
                    mission -> openScanner()
                    ringing -> {
                        SleepAlarmRingingService.dismiss(this)
                        finishAndRemoveTask()
                    }
                    else -> {
                        if (SleepAlarmScheduler.dismissSnooze(this) != null) {
                            SleepMonitoringService.alarmDismissed(
                                this,
                                SleepMonitorSessionDismiss.BUTTON,
                            )
                        }
                        finishAndRemoveTask()
                    }
                }
            },
            button(top = 12),
        )
        if (mission) {
            root.addView(
                SleepAlarmUi.textButton(this, getString(R.string.sleep_alarm_emergency_short)) {
                    openEmergencyChallenge()
                },
                wrap(top = 8),
            )
        }
        if (!ringing) {
            root.addView(
                SleepAlarmUi.textButton(this, getString(R.string.sleep_alarm_back_to_snooze)) {
                    finishAndRemoveTask()
                },
                wrap(top = if (mission) 0 else 8),
            )
        }
        setContentView(root)
    }

    /** Alarm icon on a soft circle that pulses while ringing. */
    private fun halo(ringing: Boolean): View {
        val frame = FrameLayout(this)
        val ring = View(this).apply {
            background = SleepAlarmUi.circle(Color.argb(70, 226, 222, 255))
        }
        // Room around the ring so its pulse is never clipped.
        frame.addView(ring, FrameLayout.LayoutParams(dp(112), dp(112), Gravity.CENTER))
        frame.addView(View(this).apply {
            background = SleepAlarmUi.circle(Color.argb(46, 226, 222, 255))
        }, FrameLayout.LayoutParams(dp(88), dp(88), Gravity.CENTER))
        frame.addView(ImageView(this).apply {
            setImageResource(android.R.drawable.ic_lock_idle_alarm)
            imageTintList = ColorStateList.valueOf(SleepAlarmUi.accent)
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER))
        if (ringing) {
            pulse = AnimatorSet().apply {
                playTogether(
                    ObjectAnimator.ofFloat(ring, View.SCALE_X, 0.8f, 1.25f).repeating(),
                    ObjectAnimator.ofFloat(ring, View.SCALE_Y, 0.8f, 1.25f).repeating(),
                    ObjectAnimator.ofFloat(ring, View.ALPHA, 0.9f, 0f).repeating(),
                )
                duration = 1600L
                start()
            }
        } else {
            ring.alpha = 0.35f
        }
        return frame
    }

    /** The current time while ringing; the next ring while snoozed. */
    private fun bigTime(ringing: Boolean, alarmAtMillis: Long): View {
        val view = if (ringing) {
            TextClock(this).apply {
                format24Hour = SleepSnoozeNotification.bigClockPattern(this@SleepAlarmActivity, true)
                format12Hour = SleepSnoozeNotification.bigClockPattern(this@SleepAlarmActivity, false)
            }
        } else {
            TextView(this).apply {
                text = SleepSnoozeNotification.clock(this@SleepAlarmActivity, alarmAtMillis, big = true)
            }
        }
        return view.apply {
            textSize = 84f
            gravity = Gravity.CENTER
            includeFontPadding = false
            setTextColor(SleepAlarmUi.onNight)
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            letterSpacing = -0.02f
        }
    }

    private fun longDate(): String {
        val locale = locale()
        val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "EEEEdMMMM")
        return SimpleDateFormat(pattern, locale).format(Date())
            .replaceFirstChar { it.titlecase(locale) }
    }

    private fun openEmergencyChallenge() {
        startActivity(
            Intent(this, SleepEmergencyChallengeActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
        )
    }

    private fun openScanner() {
        if (!SleepAlarmScheduler.beginBarcodeChallenge(this)) return
        missionError = null
        showCameraSettings = false
        if (SleepAlarmScheduler.isBarcodePauseActive(this)) {
            SleepAlarmRingingService.pauseForBarcode(this)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(
            Intent(this, BarcodeScannerActivity::class.java).apply {
                putExtra(BarcodeScannerActivity.EXTRA_ENROLLMENT, false)
            },
            SCAN_REQUEST,
        )
    }

    private fun ObjectAnimator.repeating(): ObjectAnimator = apply {
        repeatCount = ValueAnimator.INFINITE
        repeatMode = ValueAnimator.RESTART
    }

    private fun locale(): Locale = resources.configuration.locales[0] ?: Locale.getDefault()

    private fun wrap(top: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(top) }

    private fun button(top: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(60))
            .apply { topMargin = dp(top) }

    private fun dp(value: Int): Int = SleepAlarmUi.dp(this, value)

    private companion object {
        const val SCAN_REQUEST = BarcodeScannerActivity.RESULT_SUCCESS + 9000
    }
}
