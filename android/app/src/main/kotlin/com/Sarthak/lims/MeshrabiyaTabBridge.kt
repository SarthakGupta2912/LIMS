package com.Sarthak.lims

import android.app.Activity
import android.net.Uri
import com.ustadmobile.meshrabiya.vnet.wifi.ConnectBand
import com.ustadmobile.meshrabiya.vnet.wifi.HotspotType
import com.ustadmobile.meshrabiya.ext.addressToDotNotation
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import java.io.File
import java.net.InetAddress
import java.time.Duration
import okhttp3.OkHttpClient

/** Separate presentation bridge; shares the existing node without changing invoice transport. */
class MeshrabiyaTabBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val mesh: CustomMeshController,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var events: EventChannel.EventSink? = null
    private var server: MeshrabiyaTransferServer? = null
    private var observing = false
    private var nodeState: Map<String, Any?> = emptyMap()

    init {
        EventChannel(messenger, "lims/meshrabiya/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
                emit()
            }
            override fun onCancel(arguments: Any?) { events = null }
        })
        MethodChannel(messenger, "lims/meshrabiya").setMethodCallHandler { call, result ->
            scope.launch {
                try {
                    when (call.method) {
                        "start" -> start()
                        "hotspot" -> {
                            val response = mesh.virtualNode().setWifiHotspotEnabled(
                                enabled = call.argument<Boolean>("enabled") == true,
                                preferredBand = ConnectBand.valueOf(call.argument<String>("band") ?: "BAND_2GHZ"),
                                hotspotType = HotspotType.valueOf(call.argument<String>("type") ?: "AUTO"),
                            )
                            if (response != null && response.errorCode != 0)
                                error("ERROR enabling incoming connections: ${response.errorCode}")
                        }
                        "send" -> withContext(Dispatchers.IO) {
                            requireServer().sendFile(
                                Uri.fromFile(File(requireNotNull(call.argument<String>("path")))),
                                InetAddress.getByName(requireNotNull(call.argument<String>("address"))),
                            )
                        }
                        "accept", "decline", "delete" -> withContext(Dispatchers.IO) {
                            requireServer().incomingAction(
                                call.method,
                                requireNotNull(call.argument<Int>("id")),
                                requireNotNull(call.argument<String>("host")),
                                requireNotNull(call.argument<Long>("receivedAt")),
                            )
                        }
                        else -> { result.notImplemented(); return@launch }
                    }
                    result.success(snapshot())
                } catch (error: Exception) {
                    result.error("MESHRABIYA_ERROR", error.message, null)
                }
            }
        }
    }

    private suspend fun start() {
        mesh.start { }
        val node = mesh.virtualNode()
        if (server == null) {
            val client = OkHttpClient.Builder().socketFactory(node.socketFactory)
                .connectTimeout(Duration.ofSeconds(30)).readTimeout(Duration.ofSeconds(30))
                .writeTimeout(Duration.ofSeconds(30)).build()
            server = MeshrabiyaTransferServer(
                activity.applicationContext, client, node.address,
                File(activity.filesDir, "meshrabiya_receive"),
            ) { scope.launch { emit() } }.also { it.start() }
        }
        if (!observing) {
            observing = true
            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                node.state.collect { state ->
                    val config = state.wifiState.connectConfig
                    val station = state.wifiState.wifiStationState
                    nodeState = mapOf(
                        "address" to node.address.hostAddress,
                        "connectUri" to state.connectUri,
                        "hotspotEnabled" to (config != null),
                        "hotspotStarting" to state.wifiState.hotspotIsStarting,
                        "supports5Ghz" to node.meshrabiyaWifiManager.is5GhzSupported,
                        "ssid" to config?.ssid,
                        "band" to config?.band?.toString(),
                        "passphrase" to config?.passphrase,
                        "linkLocal" to config?.linkLocalAddr?.hostAddress,
                        "mac" to (config?.bssid ?: config?.linkLocalToMacAddress?.toString()),
                        "port" to config?.port,
                        "stationStatus" to station.status.toString(),
                        "stationSsid" to station.config?.ssid,
                        "stationAddress" to station.config?.nodeVirtualAddr?.addressToDotNotation(),
                        "nodes" to state.originatorMessages.map { (address, message) ->
                            mapOf("address" to address.addressToDotNotation(),
                                "ping" to message.originatorMessage.pingTimeSum.toInt(),
                                "hops" to message.hopCount.toInt())
                        },
                    )
                    emit()
                }
            }
        }
    }

    private fun requireServer() = server ?: error("Open the hotspot screen first")
    private fun snapshot() = nodeState + mapOf(
        "outgoing" to (server?.outgoingSnapshot() ?: emptyList<Map<String, Any?>>()),
        "incoming" to (server?.incomingSnapshot() ?: emptyList<Map<String, Any?>>()),
    )
    private fun emit() { events?.success(snapshot()) }

    fun close() {
        server?.stop()
        scope.cancel()
        events = null
    }
}
