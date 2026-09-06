package com.workoutnotes.workout_notes.sleep

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.text.format.DateFormat
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.workoutnotes.workout_notes.R
import java.util.Date

class TraditionalAlarmActivity : Activity() {
    private var id: String? = null
    private var error: String? = null

    override fun onCreate(state: Bundle?) { super.onCreate(state); lockScreen(); id = intent.getStringExtra(TraditionalAlarmScheduler.EXTRA_ID); render() }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); id = intent.getStringExtra(TraditionalAlarmScheduler.EXTRA_ID); render() }
    override fun onBackPressed() { }

    @Deprecated("Deprecated in Android SDK")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 9911) return
        val alarmId = id ?: return
        val raw = data?.getStringExtra(BarcodeScannerActivity.EXTRA_RAW_VALUE)
        val format = data?.getStringExtra(BarcodeScannerActivity.EXTRA_FORMAT)
        if (resultCode == BarcodeScannerActivity.RESULT_SUCCESS && raw != null && format != null) {
            if (TraditionalAlarmScheduler.verifyMission(this, alarmId, raw, format)) {
                TraditionalAlarmRingingService.missionComplete(this, alarmId)
                finishAndRemoveTask()
            } else {
                error = getString(R.string.traditional_alarm_mission_wrong_code)
                render()
            }
        } else {
            error = getString(R.string.traditional_alarm_mission_cancelled)
            render()
        }
    }

    private fun lockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun render() {
        val alarmId = id ?: run { finish(); return }
        val snapshot = TraditionalAlarmScheduler.read(this, alarmId) ?: run { finish(); return }
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(dp(28), dp(48), dp(28), dp(36)); setBackgroundColor(Color.rgb(19, 24, 54)) }
        root.addView(TextView(this).apply { text = "⏰"; textSize = 56f; gravity = Gravity.CENTER })
        root.addView(TextView(this).apply { text = getString(R.string.traditional_alarm_wake_title); textSize = 26f; gravity = Gravity.CENTER; setTextColor(Color.WHITE) })
        root.addView(TextView(this).apply { text = DateFormat.getTimeFormat(this@TraditionalAlarmActivity).format(Date(snapshot.alarmAtMillis)); textSize = 68f; gravity = Gravity.CENTER; setTextColor(Color.WHITE) })
        root.addView(TextView(this).apply { text = getString(if (snapshot.requiresMission) R.string.traditional_alarm_mission_body else R.string.traditional_alarm_ringing_body); textSize = 16f; gravity = Gravity.CENTER; setTextColor(Color.LTGRAY) })
        if (error != null) root.addView(TextView(this).apply { text = error; gravity = Gravity.CENTER; setTextColor(Color.rgb(255, 180, 180)) })
        root.addView(TextView(this), LinearLayout.LayoutParams(1, 0, 1f))
        if (snapshot.snoozeEnabled && snapshot.snoozeCount < snapshot.maxSnoozes) root.addView(Button(this).apply { text = getString(R.string.traditional_alarm_snooze_detail, snapshot.snoozeMinutes, snapshot.snoozeCount + 1, snapshot.maxSnoozes); setOnClickListener { TraditionalAlarmRingingService.snooze(this@TraditionalAlarmActivity, alarmId); finishAndRemoveTask() } }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(54)))
        root.addView(Button(this).apply { text = getString(if (snapshot.requiresMission) R.string.traditional_alarm_open_mission else R.string.traditional_alarm_dismiss); setOnClickListener { if (snapshot.requiresMission) startActivityForResult(Intent(this@TraditionalAlarmActivity, BarcodeScannerActivity::class.java).apply { putExtra(BarcodeScannerActivity.EXTRA_ENROLLMENT, false) }, 9911) else { TraditionalAlarmRingingService.dismiss(this@TraditionalAlarmActivity, alarmId); finishAndRemoveTask() } } }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(56)).apply { topMargin = dp(12) })
        setContentView(root)
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
