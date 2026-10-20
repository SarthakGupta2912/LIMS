// Bridges Flutter calls to the WifiP2pManager session.
package com.nankai.flutter_nearby_connections

import android.app.Activity
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FlutterNearbyConnectionsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var session: WifiDirectSession? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "flutter_nearby_connections")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "init_nearby_service") {
                NearbyLog.info(TAG, "init requested strategy=${call.argument<Int>("strategy")}")
                if (call.argument<Int>("strategy") != 3) {
                    result.error("UNSUPPORTED_STRATEGY", "Only Wi_Fi_P2P is supported", null)
                    return
                }
                val host = activity ?: error("Plugin is not attached to an Activity")
                session?.close()
                session = WifiDirectSession(host, channel, call.argument<String>("deviceName").orEmpty())
                NearbyLog.info(TAG, "session constructed; reporting channel initialized")
                result.success(null)
                channel.invokeMethod("nearby_running", true)
                return
            }
            val active = session ?: error("Nearby service is not initialized")
            when (call.method) {
                "start_advertising_peer" -> active.startAdvertising(call.argument<String>("deviceName").orEmpty())
                "stop_advertising_peer" -> active.stopAdvertising()
                "start_browsing_for_peers" -> {
                    NearbyLog.info(TAG, "start discovery requested by Dart")
                    active.startDiscovery()
                }
                "stop_browsing_for_peers" -> active.stopDiscovery()
                "invite_peer" -> active.connect(call.argument<String>("deviceId")!!)
                "disconnect_peer" -> active.disconnect(call.argument<String>("deviceId")!!)
                "send_message" -> active.send(call.argument<String>("deviceId")!!, call.argument<String>("message")!!)
                "close_nearby_service" -> { active.close(); session = null }
                else -> { result.notImplemented(); return }
            }
            result.success(null)
        } catch (error: Exception) {
            Log.e(TAG, "method ${call.method} failed", error)
            result.error("WIFI_DIRECT_ERROR", error.message, null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onDetachedFromActivity() { activity = null }
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        session?.close()
        session = null
        channel.setMethodCallHandler(null)
    }

    companion object { private const val TAG = "LimsWifiDirect" }
}
