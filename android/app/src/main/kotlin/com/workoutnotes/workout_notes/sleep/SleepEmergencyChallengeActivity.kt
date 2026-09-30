package com.workoutnotes.workout_notes.sleep

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.CountDownTimer
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import com.workoutnotes.workout_notes.R
import kotlin.math.ceil
import kotlin.math.roundToInt

class SleepEmergencyChallengeActivity : Activity() {
    private lateinit var progressBar: ProgressBar
    private lateinit var countdownView: TextView
    private lateinit var counterView: TextView
    private lateinit var tapButton: android.widget.Button
    private var timer: CountDownTimer? = null
    private var closing = false
    private var completed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SleepAlarmUi.configureWindow(this)
        if (!SleepAlarmScheduler.beginEmergencyChallenge(this)) {
            finish()
            return
        }
        SleepAlarmRingingService.pauseForEmergency(this)
        render()
        startTimer()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!closing) {
            startTimer()
            updateProgress()
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        abortChallenge()
    }

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations && !isFinishing && !closing && !completed) {
            abortChallenge()
        }
    }

    override fun onDestroy() {
        timer?.cancel()
        super.onDestroy()
    }

    private fun render() {
        val snoozed = SleepAlarmScheduler.read(this)?.isSnoozed == true
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(56), dp(28), dp(28))
            background = SleepAlarmUi.background(ringing = !snoozed)
        }

        progressBar = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal,
        ).apply {
            max = 1000
            progress = 1000
            progressTintList = ColorStateList.valueOf(Color.rgb(226, 222, 255))
            progressBackgroundTintList = ColorStateList.valueOf(Color.argb(90, 226, 222, 255))
        }
        root.addView(progressBar, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(5),
        ))

        countdownView = TextView(this).apply {
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(218, 215, 237))
        }
        root.addView(countdownView, margins(top = 18))

        root.addView(TextView(this).apply {
            text = getString(R.string.sleep_alarm_emergency_title)
            textSize = 28f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
        }, margins(top = 28))

        root.addView(TextView(this).apply {
            text = getString(R.string.sleep_alarm_emergency_instruction)
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(218, 215, 237))
        }, margins(top = 12))

        val spacer = View(this)
        root.addView(spacer, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ))

        counterView = TextView(this).apply {
            textSize = 48f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL))
        }
        root.addView(counterView)

        tapButton = SleepAlarmUi.pillButton(
            this,
            getString(R.string.sleep_alarm_emergency_tap_button),
            filled = true,
        ) { onEmergencyTap() }
        root.addView(tapButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(76),
        ).apply { topMargin = dp(20) })

        root.addView(TextView(this).apply {
            text = getString(
                if (snoozed) {
                    R.string.sleep_alarm_emergency_cancel_hint_snoozed
                } else {
                    R.string.sleep_alarm_emergency_cancel_hint
                },
            )
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(185, 181, 209))
        }, margins(top = 14))

        setContentView(root)
        updateProgress()
    }

    private fun startTimer() {
        timer?.cancel()
        val remaining = SleepAlarmScheduler.emergencyRemainingMillis(this)
        if (remaining <= 0L) {
            timeoutChallenge()
            return
        }
        timer = object : CountDownTimer(remaining, 100L) {
            override fun onTick(millisUntilFinished: Long) {
                updateProgress(millisUntilFinished)
            }

            override fun onFinish() {
                timeoutChallenge()
            }
        }.start()
    }

    private fun updateProgress(remainingMillis: Long =
        SleepAlarmScheduler.emergencyRemainingMillis(this)) {
        if (!::progressBar.isInitialized) return
        val safeRemaining = remainingMillis.coerceIn(
            0L,
            SleepAlarmScheduler.EMERGENCY_CHALLENGE_DURATION_MILLIS,
        )
        progressBar.progress = (
            safeRemaining.toDouble() /
                SleepAlarmScheduler.EMERGENCY_CHALLENGE_DURATION_MILLIS * 1000
            ).roundToInt()
        countdownView.text = getString(
            R.string.sleep_alarm_emergency_time_left,
            ceil(safeRemaining / 1000.0).toInt(),
        )
        val taps = SleepAlarmScheduler.emergencyTaps(this)
        counterView.text = getString(R.string.sleep_alarm_emergency_count, taps)
        tapButton.text = getString(R.string.sleep_alarm_emergency_tap_button)
    }

    private fun onEmergencyTap() {
        if (closing || completed) return
        val taps = SleepAlarmRingingService.tapEmergency(this)
        if (taps >= SleepAlarmScheduler.MAX_EMERGENCY_TAPS) {
            completed = true
            timer?.cancel()
            finishAndRemoveTask()
            return
        }
        if (taps == 0 && !SleepAlarmScheduler.isEmergencyChallengeActive(this)) {
            timeoutChallenge()
            return
        }
        updateProgress()
    }

    private fun timeoutChallenge() {
        if (closing || completed) return
        closing = true
        timer?.cancel()
        SleepAlarmRingingService.resumeAfterEmergency(this)
        finish()
    }

    private fun abortChallenge() {
        timeoutChallenge()
    }

    private fun margins(top: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(top) }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
