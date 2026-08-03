package com.workoutnotes.workout_notes.sleep

import android.content.Context

/**
 * Release gate for the licensed acoustic staging model.
 *
 * Both the quantized model and its signed model contract must ship in the APK.
 * Merely having microphone data never enables sleep-stage predictions.
 */
object SleepStageModelGate {
    private const val MODEL_ASSET =
        "flutter_assets/assets/models/sleep_staging_model.tflite"
    private const val CONTRACT_ASSET =
        "flutter_assets/assets/models/sleep_staging_model.json"

    // Flip only together with the reviewed LiteRT DSP/inference implementation.
    private const val RUNTIME_IMPLEMENTED = false

    fun capabilities(context: Context): Map<String, Any?> {
        val modelPresent = assetExists(context, MODEL_ASSET)
        val contractPresent = assetExists(context, CONTRACT_ASSET)
        val available = modelPresent && contractPresent && RUNTIME_IMPLEMENTED
        return mapOf(
            "sleep_staging_available" to available,
            "sleep_staging_model_present" to modelPresent,
            "sleep_staging_contract_present" to contractPresent,
            "sleep_staging_runtime_ready" to RUNTIME_IMPLEMENTED,
            "sleep_staging_reason" to when {
                available -> null
                !modelPresent || !contractPresent -> "licensed_model_missing"
                else -> "runtime_not_implemented"
            },
        )
    }

    private fun assetExists(context: Context, name: String): Boolean = try {
        context.assets.open(name).use { true }
    } catch (_: Throwable) {
        false
    }
}
