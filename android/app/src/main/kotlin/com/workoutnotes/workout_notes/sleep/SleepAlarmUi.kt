package com.workoutnotes.workout_notes.sleep

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/** Colours, window set-up and buttons shared by the native sleep alarm screens. */
internal object SleepAlarmUi {
    val night = Color.rgb(12, 15, 36)
    val onNight = Color.WHITE
    val muted = Color.rgb(196, 192, 222)
    val accent = Color.rgb(226, 222, 255)
    val onAccent = Color.rgb(31, 27, 58)
    val error = Color.rgb(255, 190, 190)

    /** Night fading into dawn while ringing; plain night during a snooze. */
    fun background(ringing: Boolean) = GradientDrawable(
        GradientDrawable.Orientation.TOP_BOTTOM,
        if (ringing) {
            intArrayOf(night, Color.rgb(45, 37, 92), Color.rgb(122, 76, 118))
        } else {
            intArrayOf(night, Color.rgb(20, 25, 56), Color.rgb(30, 34, 72))
        },
    )

    fun configureWindow(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setShowWhenLocked(true)
            activity.setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            activity.window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        activity.window.statusBarColor = night
        activity.window.navigationBarColor = night
    }

    /** Rounded pill: filled for the main action, outlined for the others. */
    fun pillButton(
        activity: Activity,
        label: String,
        filled: Boolean,
        onClick: () -> Unit,
    ): Button = Button(activity).apply {
        text = label
        isAllCaps = false
        textSize = 17f
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        stateListAnimator = null
        elevation = 0f
        setTextColor(if (filled) onAccent else onNight)
        val shape = GradientDrawable().apply {
            cornerRadius = dp(activity, 32).toFloat()
            if (filled) {
                setColor(accent)
            } else {
                setColor(Color.argb(28, 255, 255, 255))
                setStroke(dp(activity, 1), Color.argb(90, 255, 255, 255))
            }
        }
        background = RippleDrawable(
            ColorStateList.valueOf(Color.argb(if (filled) 50 else 40, 255, 255, 255)),
            shape,
            null,
        )
        setOnClickListener { onClick() }
    }

    /** Borderless text action (emergency, back to snooze). */
    fun textButton(activity: Activity, label: String, onClick: () -> Unit): TextView =
        TextView(activity).apply {
            text = label
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(muted)
            setPadding(dp(activity, 16), dp(activity, 14), dp(activity, 16), dp(activity, 14))
            isClickable = true
            isFocusable = true
            val outValue = TypedValue()
            activity.theme.resolveAttribute(
                android.R.attr.selectableItemBackgroundBorderless,
                outValue,
                true,
            )
            setBackgroundResource(outValue.resourceId)
            setOnClickListener { onClick() }
        }

    fun circle(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
    }

    fun dp(activity: Activity, value: Int): Int =
        (value * activity.resources.displayMetrics.density).toInt()
}
