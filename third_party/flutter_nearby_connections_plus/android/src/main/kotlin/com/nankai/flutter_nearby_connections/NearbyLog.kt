package com.nankai.flutter_nearby_connections

import android.util.Log

internal object NearbyLog {
    fun info(tag: String, message: String) {
        if (BuildConfig.DEBUG) Log.i(tag, message)
    }
}
