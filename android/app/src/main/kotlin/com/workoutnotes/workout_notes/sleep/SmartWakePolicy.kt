package com.workoutnotes.workout_notes.sleep

/**
 * When a smart alarm rings before its deadline. Mirror of
 * `lib/services/smart_wake_policy.dart` (used by the replay tool); both are
 * checked against `test/fixtures/sleep_wake_parity.json`.
 *
 * Inside the window before the deadline, the alarm rings at the first
 * 30-second window whose probability of sleep falls below [threshold]: the
 * person is moving or already awake. The filter starts every night assuming
 * the person is awake, so nothing fires until it has seen [ARMING_SECONDS] of
 * confident sleep. The deadline itself is an ordinary exact alarm scheduled
 * separately; this policy can only ring earlier, never later.
 */
class SmartWakePolicy(private val threshold: Double) {
    companion object {
        const val ARMING_SECONDS = 10 * 60
        const val ARMING_PROBABILITY = 0.8
        const val AWAKE_PROBABILITY = 0.3
        const val TRIGGER_AWAKE = "awake"
        const val TRIGGER_STIRRING = "stirring"
        const val TRIGGER_DEADLINE = "deadline"
    }

    private var confidentSleepSeconds = 0

    val isArmed: Boolean get() = confidentSleepSeconds >= ARMING_SECONDS

    /**
     * Feeds one window ending at [nowMillis] and returns the trigger reason
     * when the alarm should ring now, or null.
     */
    fun onWindow(
        decision: SleepWakeFilter.Decision,
        seconds: Int,
        nowMillis: Long,
        windowStartMillis: Long,
        deadlineMillis: Long,
    ): String? {
        if (decision.validSignal && decision.sleepProbability >= ARMING_PROBABILITY) {
            confidentSleepSeconds += seconds.coerceAtLeast(0)
        }
        if (!isArmed || !decision.validSignal) return null
        if (nowMillis < windowStartMillis || nowMillis >= deadlineMillis) return null
        if (decision.sleepProbability >= threshold) return null
        return if (decision.sleepProbability < AWAKE_PROBABILITY) {
            TRIGGER_AWAKE
        } else {
            TRIGGER_STIRRING
        }
    }
}
