package com.workoutnotes.workout_notes.common

import org.json.JSONArray
import org.json.JSONObject

/** Conversions between `org.json` trees and plain Kotlin maps/lists (for channel replies and spools). */
object JsonMaps {
    fun toMap(value: JSONObject): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        val keys = value.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = toValue(value.get(key))
        }
        return result
    }

    fun toValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> toMap(value)
        is JSONArray -> (0 until value.length()).map { toValue(value.get(it)) }
        else -> value
    }
}
