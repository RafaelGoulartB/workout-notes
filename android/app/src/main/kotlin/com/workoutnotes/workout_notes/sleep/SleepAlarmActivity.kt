package com.workoutnotes.workout_notes.sleep

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.provider.Settings
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
    private var protectedAlarm = false
    private var missionError: String? = null
    private var showCameraSettings = false

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

    @Deprecated("Deprecated in Android SDK")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != BarcodeScannerActivity.RESULT_SUCCESS + 9000) return
        if (resultCode != BarcodeScannerActivity.RESULT_SUCCESS || data == null) {
            if (data?.getBooleanExtra(BarcodeScannerActivity.EXTRA_CAMERA_DENIED, false) == true) {
                missionError = getString(R.string.sleep_alarm_mission_camera_denied)
                showCameraSettings = true
                render(intent)
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
            missionError = getString(R.string.sleep_alarm_mission_wrong_code)
            render(intent)
        }
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
        val snapshot = SleepAlarmScheduler.read(this)
        protectedAlarm = snapshot?.requiresMission == true

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
            text = if (protectedAlarm) {
                getString(R.string.sleep_alarm_mission_body)
            } else {
                getString(R.string.sleep_alarm_wake_message)
            }
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(218, 215, 237))
        }, margins(top = 4))
        if (protectedAlarm && missionError != null) {
            root.addView(TextView(this).apply {
                text = missionError
                textSize = 15f
                gravity = Gravity.CENTER
                setTextColor(Color.rgb(255, 190, 190))
            }, margins(top = 12))
            if (showCameraSettings) {
                root.addView(Button(this).apply {
                    text = getString(R.string.sleep_alarm_open_camera_settings)
                    isAllCaps = false
                    setOnClickListener {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName"),
                            ),
                        )
                    }
                }, margins(top = 8))
            }
        }
        root.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        if (protectedAlarm) {
            root.addView(Button(this).apply {
                text = getString(R.string.sleep_alarm_open_mission)
                textSize = 17f
                isAllCaps = false
                setTextColor(Color.rgb(35, 31, 63))
                backgroundTintList = ColorStateList.valueOf(Color.rgb(226, 222, 255))
                setOnClickListener { openScanner() }
            }, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(56),
            ))
            root.addView(Button(this).apply {
                text = getString(R.string.sleep_alarm_emergency_open)
                textSize = 15f
                isAllCaps = false
                setOnClickListener { openEmergencyChallenge() }
            }, margins(top = 12).apply {
                width = LinearLayout.LayoutParams.MATCH_PARENT
                height = dp(52)
            })
        } else {
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
        }
        setContentView(root)
    }

    private fun openEmergencyChallenge() {
        startActivity(
            Intent(this, SleepEmergencyChallengeActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
        )
    }

    private fun openScanner() {
        missionError = null
        showCameraSettings = false
        startActivityForResult(
            Intent(this, BarcodeScannerActivity::class.java).apply {
                putExtra(BarcodeScannerActivity.EXTRA_ENROLLMENT, false)
            },
            BarcodeScannerActivity.RESULT_SUCCESS + 9000,
        )
    }

    private fun margins(top: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(top) }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
