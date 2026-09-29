package com.workoutnotes.workout_notes.common

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

object NotificationChannels {
    /**
     * Creates (or updates) a notification channel on API 26+. Creating an
     * existing channel leaves the user's settings intact, so this is safe to
     * call before every notification.
     */
    fun ensure(
        context: Context,
        id: String,
        name: CharSequence,
        importance: Int,
        configure: NotificationChannel.() -> Unit = {},
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(id, name, importance).apply(configure),
        )
    }

    /** No channel sound and no channel vibration (the app plays its own, or none). */
    fun NotificationChannel.silent() {
        setSound(null, null)
        enableVibration(false)
    }
}
