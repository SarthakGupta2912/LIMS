package com.Sarthak.lims

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.app.NotificationManager
import android.media.AudioManager
import android.os.Environment
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.app.Activity
import android.companion.AssociationRequest
import android.companion.CompanionDeviceManager
import android.companion.WifiDeviceFilter
import android.content.Intent
import android.content.IntentSender
import android.provider.Settings
import android.net.wifi.ScanResult
import android.os.Handler
import android.os.Looper
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.util.Log
import com.ustadmobile.meshrabiya.vnet.MeshrabiyaConnectLink
import java.util.regex.Pattern

class MainActivity : FlutterActivity() {
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkRequestTimeout: Runnable? = null
    private lateinit var customMesh: CustomMeshController
    private lateinit var meshrabiyaTab: MeshrabiyaTabBridge
    private var customMeshEvents: EventChannel.EventSink? = null
    private var customMeshTransportEvents: EventChannel.EventSink? = null
    private var pendingMeshConnect: MethodChannel.Result? = null
    private var pendingMeshUri: String? = null

    companion object {
        private const val MESH_ASSOCIATE_REQUEST = 71
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        customMesh = CustomMeshController(applicationContext)
        meshrabiyaTab = MeshrabiyaTabBridge(this, flutterEngine.dartExecutor.binaryMessenger, customMesh)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "lims/custom_mesh/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    customMeshEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    customMeshEvents = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lims/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "publicDownloadsPath") {
                    result.success(
                        Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOWNLOADS,
                        ).absolutePath,
                    )
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lims/platform")
            .setMethodCallHandler { call, result ->
                if (call.method == "sdkInt") {
                    result.success(Build.VERSION.SDK_INT)
                } else if (call.method == "isWifiEnabled") {
                    result.success(getSystemService(WifiManager::class.java).isWifiEnabled)
                } else if (call.method == "openWifiSettings") {
                    startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lims/buzz")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        BuzzVibrationController.start(
                            applicationContext,
                            call.argument<String>("eventId").orEmpty(),
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        BuzzVibrationController.stop(call.argument<String>("eventId"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lims/wifi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startShopHotspot" -> startShopHotspot(result)
                    "stopShopHotspot" -> {
                        hotspotReservation?.close()
                        hotspotReservation = null
                        result.success(null)
                    }
                    "connectToShopHotspot" -> connectToShopHotspot(
                        call.argument<String>("ssid").orEmpty(),
                        call.argument<String>("password").orEmpty(),
                        result,
                    )
                    "disconnectFromShopHotspot" -> {
                        releaseRequestedNetwork()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lims/custom_mesh")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        runMesh(result) {
                            customMesh.start { state ->
                                customMeshEvents?.success(state)
                            }
                        }
                    }
                    "enableHotspot" -> runMesh(result) {
                        customMesh.enableHotspot(
                            call.argument<String>("band") ?: "BAND_5GHZ",
                            call.argument<String>("hotspotType") ?: "AUTO",
                        )
                    }
                    "disableHotspot" -> runMesh(result) { customMesh.disableHotspot() }
                    "connect" -> connectMeshWithQr(call.argument<String>("uri").orEmpty(), result)
                    "disconnect" -> runMesh(result) { customMesh.disconnect() }
                    "state" -> result.success(customMesh.state())
                    "qrNodeAddress" -> {
                        try {
                            val config = MeshrabiyaConnectLink.parseUri(
                                call.argument<String>("uri").orEmpty().replace("custommesh://", "meshrabiya://"),
                            ).hotspotConfig ?: error("The mesh QR has no hotspot configuration")
                            val bytes = java.nio.ByteBuffer.allocate(4).putInt(config.nodeVirtualAddr).array()
                            result.success(java.net.InetAddress.getByAddress(bytes).hostAddress)
                        } catch (error: Exception) {
                            result.error("INVALID_MESH_URI", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lims/custom_mesh/transport")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            customMesh.startTransport(call.argument<ByteArray>("advertisement")) { event ->
                                emitMeshTransport(event)
                            }
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("CUSTOM_MESH_TRANSPORT_ERROR", error.message, null)
                        }
                    }
                    "stop" -> {
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                withContext(Dispatchers.IO) { customMesh.stopTransport() }
                                result.success(null)
                            } catch (error: Exception) {
                                result.error("CUSTOM_MESH_TRANSPORT_ERROR", error.message, null)
                            }
                        }
                    }
                    "discover" -> {
                        customMesh.discoverTransport { event ->
                            emitMeshTransport(event)
                        }
                        result.success(null)
                    }
                    "connect" -> {
                        customMesh.connectTransport(
                            call.argument<String>("address").orEmpty(),
                            call.argument<Int>("port") ?: 0,
                            call.argument<String>("peerId").orEmpty(),
                        ) { event -> emitMeshTransport(event) }
                        result.success(null)
                    }
                    "send" -> {
                        val peerId = call.argument<String>("peerId").orEmpty()
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                withContext(Dispatchers.IO) {
                                    customMesh.sendTransport(peerId, bytes)
                                }
                                result.success(null)
                            } catch (error: Exception) {
                                Log.e("CustomMesh", "Mesh frame send failed", error)
                                result.error(
                                    "CUSTOM_MESH_TRANSPORT_ERROR",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                        }
                    }
                    "disconnect" -> {
                        customMesh.disconnectTransport(call.argument<String>("peerId").orEmpty())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "lims/custom_mesh/transport_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    customMeshTransportEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    customMeshTransportEvents = null
                }
            })
    }

    private fun runMesh(
        result: MethodChannel.Result,
        operation: suspend () -> Map<String, Any?>,
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val values = operation()
                customMeshEvents?.success(values)
                result.success(values)
            } catch (error: Exception) {
                Log.e("CustomMesh", "Custom Mesh operation failed", error)
                result.error("CUSTOM_MESH_ERROR", error.message, null)
            }
        }
    }

    private fun emitMeshTransport(event: Map<String, Any?>) {
        Handler(Looper.getMainLooper()).post { customMeshTransportEvents?.success(event) }
    }

    private fun connectMeshWithQr(uri: String, result: MethodChannel.Result) {
        if (uri.isBlank()) {
            result.error("INVALID_MESH_URI", "The mesh QR code is empty", null)
            return
        }
        if (pendingMeshConnect != null) {
            result.error("CONNECT_BUSY", "Another mesh connection is awaiting approval", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val state = customMesh.connect(uri)
                customMeshEvents?.success(state)
                result.success(state)
            } catch (error: Exception) {
                if (error.message != "MESH_BSSID_REQUIRED" || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.error("CUSTOM_MESH_ERROR", error.message, null)
                    return@launch
                }
                requestMeshAssociation(uri, result)
            }
        }
    }

    private fun requestMeshAssociation(uri: String, result: MethodChannel.Result) {
        val config = try {
            MeshrabiyaConnectLink.parseUri(
                uri.replace("custommesh://", "meshrabiya://"),
            ).hotspotConfig ?: throw IllegalArgumentException("The mesh QR has no hotspot configuration")
        } catch (error: Exception) {
            result.error("INVALID_MESH_URI", error.message, null)
            return
        }
        pendingMeshConnect = result
        pendingMeshUri = uri
        val request = AssociationRequest.Builder()
            .addDeviceFilter(
                WifiDeviceFilter.Builder()
                    .setNamePattern(Pattern.compile(Pattern.quote(config.ssid)))
                    .build(),
            )
            .setSingleDevice(true)
            .build()
        try {
            getSystemService(CompanionDeviceManager::class.java).associate(
                request,
                object : CompanionDeviceManager.Callback() {
                    override fun onDeviceFound(chooserLauncher: IntentSender) {
                        try {
                            startIntentSenderForResult(chooserLauncher, MESH_ASSOCIATE_REQUEST, null, 0, 0, 0)
                        } catch (error: Exception) {
                            finishPendingMeshConnect(error.message ?: "Could not open hotspot chooser")
                        }
                    }

                    override fun onFailure(error: CharSequence?) {
                        finishPendingMeshConnect("Mesh hotspot not found: $error")
                    }
                },
                null,
            )
        } catch (error: Exception) {
            finishPendingMeshConnect(error.message ?: "Could not find mesh hotspot")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != MESH_ASSOCIATE_REQUEST) return
        val callback = pendingMeshConnect
        val uri = pendingMeshUri
        pendingMeshConnect = null
        pendingMeshUri = null
        if (callback == null || uri == null) return
        if (resultCode != Activity.RESULT_OK) {
            callback.error("CONNECT_CANCELLED", "Mesh hotspot selection was cancelled", null)
            return
        }
        @Suppress("DEPRECATION")
        val device = data?.getParcelableExtra<ScanResult>(CompanionDeviceManager.EXTRA_DEVICE)
        val bssid = device?.BSSID
        if (bssid.isNullOrBlank()) {
            callback.error("CONNECT", "The selected mesh hotspot has no BSSID", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val state = customMesh.connect(uri, bssid)
                customMeshEvents?.success(state)
                callback.success(state)
            } catch (error: Exception) {
                callback.error("CUSTOM_MESH_ERROR", error.message, null)
            }
        }
    }

    private fun finishPendingMeshConnect(message: String) {
        pendingMeshConnect?.error("CONNECT", message, null)
        pendingMeshConnect = null
        pendingMeshUri = null
    }

    private fun startShopHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "Local hotspot requires Android 8 or newer", null)
            return
        }
        hotspotReservation?.let { reservation ->
            val config = reservation.wifiConfiguration
            result.success(mapOf("ssid" to config?.SSID, "password" to config?.preSharedKey))
            return
        }
        val wifi = getSystemService(WifiManager::class.java)
        wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
            override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                hotspotReservation = reservation
                val config = reservation.wifiConfiguration
                result.success(mapOf("ssid" to config?.SSID, "password" to config?.preSharedKey))
            }

            override fun onFailed(reason: Int) {
                result.error("HOTSPOT_FAILED", "Android could not start the in-app hotspot (code $reason)", null)
            }
        }, Handler(Looper.getMainLooper()))
    }

    private fun connectToShopHotspot(ssid: String, password: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "In-app Wi-Fi connection requires Android 10 or newer", null)
            return
        }
        val wifi = getSystemService(WifiManager::class.java)
        if (!wifi.isWifiEnabled) {
            result.error(
                "WIFI_DISABLED",
                "Wi-Fi is turned off. Turn on Wi-Fi and scan the shop QR again.",
                null,
            )
            return
        }
        if (ssid.isBlank() || password.isBlank()) {
            result.error("INVALID_NETWORK", "SSID and password are required", null)
            return
        }
        val connectivity = getSystemService(ConnectivityManager::class.java)
        releaseRequestedNetwork()
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(password)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            // The shop hotspot is a local peer network and does not provide
            // internet access. This keeps Android's request in-app.
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        var completed = false
        lateinit var callback: ConnectivityManager.NetworkCallback
        fun complete(action: () -> Unit) {
            if (completed) return
            completed = true
            networkRequestTimeout?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
            networkRequestTimeout = null
            action()
        }
        callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val capabilities = connectivity.getNetworkCapabilities(network)
                if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true) return
                complete {
                    if (connectivity.bindProcessToNetwork(network)) {
                        result.success(null)
                    } else {
                        runCatching { connectivity.unregisterNetworkCallback(callback) }
                        networkCallback = null
                        result.error("WIFI_BIND_FAILED", "Connected to Wi-Fi but could not use that network", null)
                    }
                }
            }

            override fun onUnavailable() {
                complete {
                    networkCallback = null
                    result.error("WIFI_UNAVAILABLE", "Could not connect to that Wi-Fi network", null)
                }
            }

            override fun onLost(network: Network) {
                if (networkCallback === callback) {
                    connectivity.bindProcessToNetwork(null)
                    networkCallback = null
                }
            }
        }
        val timeout = Runnable {
            complete {
                runCatching { connectivity.unregisterNetworkCallback(callback) }
                if (networkCallback === callback) networkCallback = null
                result.error("WIFI_TIMEOUT", "Could not connect to the shop Wi-Fi hotspot. Keep Wi-Fi enabled and try again.", null)
            }
        }
        networkCallback = callback
        networkRequestTimeout = timeout
        Handler(Looper.getMainLooper()).postDelayed(timeout, 20_000)
        try {
            connectivity.requestNetwork(request, callback, 18_000)
        } catch (error: Exception) {
            complete {
                networkCallback = null
                result.error("WIFI_REQUEST_FAILED", error.message ?: "Could not request that Wi-Fi network", null)
            }
        }
    }

    private fun releaseRequestedNetwork() {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        networkRequestTimeout?.let { Handler(Looper.getMainLooper()).removeCallbacks(it) }
        networkRequestTimeout = null
        networkCallback?.let { callback ->
            runCatching { connectivity.unregisterNetworkCallback(callback) }
        }
        networkCallback = null
        connectivity.bindProcessToNetwork(null)
    }

    override fun onDestroy() {
        if (::meshrabiyaTab.isInitialized) meshrabiyaTab.close()
        finishPendingMeshConnect("Mesh connection was interrupted")
        if (::customMesh.isInitialized) customMesh.close()
        customMeshEvents = null
        hotspotReservation?.close()
        releaseRequestedNetwork()
        super.onDestroy()
    }
}

private object BuzzVibrationController {
    private val handler = Handler(Looper.getMainLooper())
    private var context: Context? = null
    private var activeEventId: String? = null
    private var endsAtElapsed = 0L
    private val stopRunnable = Runnable { stop(null) }
    private val cycleRunnable = object : Runnable {
        override fun run() {
            val appContext = context
            if (activeEventId == null ||
                appContext == null ||
                android.os.SystemClock.elapsedRealtime() >= endsAtElapsed
            ) {
                stop(null)
                return
            }
            if (vibrationAllowed(appContext)) {
                val vibrator = vibrator(appContext)
                if (!vibrator.hasVibrator()) {
                    stop(null)
                    return
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(
                        VibrationEffect.createOneShot(
                            30_000,
                            VibrationEffect.DEFAULT_AMPLITUDE,
                        ),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(30_000)
                }
            }
            handler.postDelayed(this, 60_000)
        }
    }

    fun start(context: Context, eventId: String) {
        if (eventId.isBlank()) return
        stop(null)
        this.context = context.applicationContext
        activeEventId = eventId
        endsAtElapsed = android.os.SystemClock.elapsedRealtime() + 5 * 60 * 1000L
        cycleRunnable.run()
        handler.postDelayed(stopRunnable, 5 * 60 * 1000L)
    }

    fun stop(eventId: String?) {
        if (eventId != null && eventId != activeEventId) return
        handler.removeCallbacks(stopRunnable)
        handler.removeCallbacks(cycleRunnable)
        context?.let { vibrator(it).cancel() }
        context = null
        activeEventId = null
        endsAtElapsed = 0L
    }

    private fun vibrationAllowed(context: Context): Boolean {
        return try {
            val audio = context.getSystemService(AudioManager::class.java)
            if (audio.ringerMode == AudioManager.RINGER_MODE_SILENT) return false
            val notifications = context.getSystemService(NotificationManager::class.java)
            notifications.currentInterruptionFilter ==
                NotificationManager.INTERRUPTION_FILTER_ALL
        } catch (_: SecurityException) {
            false
        }
    }

    private fun vibrator(context: Context): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
}
