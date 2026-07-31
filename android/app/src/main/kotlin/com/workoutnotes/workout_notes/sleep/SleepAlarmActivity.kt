package com.workoutnotes.workout_notes.sleep

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.workoutnotes.workout_notes.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SleepAlarmActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureLockScreen()
        render(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render(intent)
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // An alarm must be explicitly dismissed.
    }

    private fun configureLockScreen() {
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
        window.statusBarColor = Color.rgb(16, 18, 38)
        window.navigationBarColor = Color.rgb(16, 18, 38)
    }

    private fun render(intent: Intent?) {
        val alarmAt = intent?.getLongExtra(
            SleepAlarmScheduler.EXTRA_ALARM_AT,
            System.currentTimeMillis(),
        ) ?: System.currentTimeMillis()
        val locale = resources.configuration.locales[0] ?: Locale.getDefault()
        val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "Hm")
        val timeText = SimpleDateFormat(pattern, locale).format(Date(alarmAt))

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(48), dp(28), dp(36))
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.rgb(19, 24, 54), Color.rgb(55, 42, 92)),
            )
        }
        root.addView(TextView(this).apply {
            text = "☾"
            textSize = 58f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(196, 190, 255))
        })
        root.addView(TextView(this).apply {
            text = getString(R.string.sleep_alarm_good_morning)
            textSize = 24f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD)
        }, margins(top = 16))
        root.addView(TextView(this).apply {
            text = timeText
            textSize = 68f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL))
        }, margins(top = 8))
        root.addView(TextView(this).apply {
            text = getString(R.string.sleep_alarm_wake_message)
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(218, 215, 237))
        }, margins(top = 4))
        root.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        root.addView(Button(this).apply {
            text = getString(R.string.sleep_alarm_dismiss)
            textSize = 17f
            isAllCaps = false
            setTextColor(Color.rgb(35, 31, 63))
            backgroundTintList = ColorStateList.valueOf(Color.rgb(226, 222, 255))
            setOnClickListener {
                SleepAlarmRingingService.dismiss(this@SleepAlarmActivity)
                finishAndRemoveTask()
            }
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(56),
        ))
        setContentView(root)
    }

    private fun margins(top: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(top) }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
