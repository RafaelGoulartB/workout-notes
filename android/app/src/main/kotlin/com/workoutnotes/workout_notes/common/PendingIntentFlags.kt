package com.workoutnotes.workout_notes.common

import android.app.PendingIntent

/** `FLAG_IMMUTABLE` exists since API 23 and minSdk is 24, so it is always safe to set. */
object PendingIntentFlags {
    /** The usual flags for a PendingIntent that is refreshed in place. */
    const val UPDATE_IMMUTABLE: Int =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
}
