package com.workoutnotes.workout_notes.sleep

import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom

object BarcodeMissionCrypto {
    private val random = SecureRandom()

    fun newSalt(): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
    }

    fun hash(format: String, rawValue: String, salt: String): String {
        val canonical = "$salt\u0000$format\u0000$rawValue"
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(canonical.toByteArray(StandardCharsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun constantTimeEquals(left: String?, right: String?): Boolean {
        if (left == null || right == null) return false
        val a = left.toByteArray(StandardCharsets.UTF_8)
        val b = right.toByteArray(StandardCharsets.UTF_8)
        var result = a.size xor b.size
        val length = maxOf(a.size, b.size)
        for (index in 0 until length) {
            val av = if (index < a.size) a[index].toInt() else 0
            val bv = if (index < b.size) b[index].toInt() else 0
            result = result or (av xor bv)
        }
        return result == 0
    }
}
