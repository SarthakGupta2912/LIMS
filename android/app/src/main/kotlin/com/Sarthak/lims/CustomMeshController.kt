package com.Sarthak.lims

import android.content.Context
import android.os.Build
import androidx.datastore.preferences.preferencesDataStore
import com.ustadmobile.meshrabiya.vnet.AndroidVirtualNode
import com.ustadmobile.meshrabiya.vnet.MeshrabiyaConnectLink
import com.ustadmobile.meshrabiya.vnet.VirtualNode
import com.ustadmobile.meshrabiya.vnet.wifi.ConnectBand
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.Executors

private val Context.customMeshDataStore by preferencesDataStore(name = "lims_custom_mesh")

/** Owns the process-wide custom mesh node used by the Flutter bridge. */
class CustomMeshController(private val context: Context) {
    private val scope = CoroutineScope(Dispatchers.Main.immediate + Job())
    private var node: AndroidVirtualNode? = null
    private var latestState: Map<String, Any?> = emptyMap()
    private var meshDiscovery: DatagramSocket? = null
    @Volatile private var meshAdvertisement: ByteArray? = null
    private var meshAppServer: ServerSocket? = null
    private val meshSockets = mutableMapOf<String, Socket>()
    private val meshExecutor = Executors.newCachedThreadPool()

    private fun stateMap(
        address: String?,
        uri: String?,
        originatorMessages: Map<Int, VirtualNode.LastOriginatorMessage> = emptyMap(),
    ): Map<String, Any?> {
        val ready = uri?.contains("hotspot=") == true
        val nodes = originatorMessages.map { (nodeAddress, message) ->
            mapOf(
                "address" to nodeAddress,
                "ping" to message.originatorMessage.pingTimeSum.toInt(),
                "hops" to message.hopCount.toInt(),
            )
        }
        return mapOf(
            "address" to address,
            "connectUri" to uri,
            "hotspotEnabled" to ready,
            "nodes" to nodes,
        )
    }

    suspend fun start(onState: (Map<String, Any?>) -> Unit): Map<String, Any?> {
        val existing = node
        if (existing != null) {
            onState(latestState)
            return latestState
        }

        val created = AndroidVirtualNode(
            appContext = context.applicationContext,
            dataStore = context.applicationContext.customMeshDataStore,
        )
        node = created
        scope.launch {
            created.state.collect { state ->
                latestState = stateMap(
                    created.address.hostAddress,
                    state.connectUri,
                    state.originatorMessages,
                )
                onState(latestState)
            }
        }
        val state = created.state.first()
        latestState = stateMap(
            created.address.hostAddress,
            state.connectUri,
            state.originatorMessages,
        )
        onState(latestState)
        return latestState
    }

    suspend fun enableHotspot(bandName: String, hotspotTypeName: String): Map<String, Any?> {
        val active = requireNode()
        val band = runCatching { ConnectBand.valueOf(bandName) }.getOrDefault(ConnectBand.BAND_5GHZ)
        val response = active.setWifiHotspotEnabled(
            enabled = true,
            preferredBand = band,
        )
        if (response != null && response.errorCode != 0) {
            throw IllegalStateException("Mesh hotspot failed (code ${response.errorCode})")
        }
        val state = withTimeout(20_000) {
            active.state.first { it.connectUri?.contains("hotspot=") == true }
        }
        latestState = stateMap(
            active.address.hostAddress,
            state.connectUri,
            state.originatorMessages,
        )
        return latestState
    }

    suspend fun disableHotspot(): Map<String, Any?> {
        val active = requireNode()
        active.setWifiHotspotEnabled(enabled = false)
        return latestState
    }

    suspend fun connect(uri: String, bssidOverride: String? = null): Map<String, Any?> {
        val active = requireNode()
        val link = MeshrabiyaConnectLink.parseUri(
            uri.replace("custommesh://", "meshrabiya://"),
        )
        val config = link.hotspotConfig
            ?: throw IllegalArgumentException("The mesh QR code does not contain a hotspot link")
        val bssid = bssidOverride ?: config.bssid ?: active.lookupStoredBssid(config.ssid)
        if (bssid == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            throw IllegalStateException("MESH_BSSID_REQUIRED")
        }
        latestState = latestState + mapOf("connectionState" to "connecting")
        active.connectAsStation(config.copy(bssid = bssid))
        active.storeBssid(config.ssid, bssid)
        return latestState + mapOf("connectionState" to "connected")
    }

    suspend fun disconnect(): Map<String, Any?> {
        val active = requireNode()
        active.disconnectWifiStation()
        latestState = latestState + mapOf("connectionState" to "disconnected")
        return latestState
    }

    fun startTransport(advertisement: ByteArray?, emit: (Map<String, Any?>) -> Unit) {
        val active = requireNode()
        meshAdvertisement = advertisement
        if (meshDiscovery == null) {
            meshDiscovery = active.createBoundDatagramSocket(MESH_DISCOVERY_PORT)
            meshExecutor.submit { receiveMeshDiscovery(emit) }
        }
        if (advertisement != null && meshAppServer == null) {
            val appServer = ServerSocket(MESH_DATA_PORT)
            meshAppServer = appServer
            meshExecutor.submit {
                while (!appServer.isClosed) {
                    try {
                        val socket = appServer.accept()
                        val peerId = "mesh:${socket.remoteSocketAddress}"
                        synchronized(meshSockets) { meshSockets[peerId] = socket }
                        emit(mapOf("type" to "connected", "peerId" to peerId, "direction" to "incoming"))
                        meshExecutor.submit { readMeshFrames(peerId, socket, emit) }
                    } catch (_: Exception) { break }
                }
            }
            emit(mapOf("type" to "transport_ready", "port" to MESH_DATA_PORT))
        }
    }

    fun stopTransport() {
        meshAdvertisement = null
        meshDiscovery?.close(); meshDiscovery = null
        meshAppServer?.close(); meshAppServer = null
        synchronized(meshSockets) {
            meshSockets.values.forEach { it.close() }
            meshSockets.clear()
        }
    }

    fun discoverTransport(emit: (Map<String, Any?>) -> Unit) {
        val socket = meshDiscovery ?: return
        val active = requireNode()
        meshExecutor.submit {
            try {
                val data = DISCOVERY_REQUEST.toByteArray()
                // Mesh broadcasts are forwarded, but are not delivered to local sockets.
                runBlocking { active.state.first() }.originatorMessages.keys.forEach { address ->
                    val bytes = ByteBuffer.allocate(4).putInt(address).array()
                    socket.send(
                        DatagramPacket(
                            data,
                            data.size,
                            InetAddress.getByAddress(bytes),
                            MESH_DISCOVERY_PORT,
                        ),
                    )
                }
            } catch (error: Exception) {
                emit(mapOf("type" to "transport_error", "message" to (error.message ?: "Mesh discovery failed")))
            }
        }
    }

    fun connectTransport(address: String, port: Int, peerId: String, emit: (Map<String, Any?>) -> Unit) {
        val active = requireNode()
        meshExecutor.submit {
            try {
                val socket = active.socketFactory.createSocket(InetAddress.getByName(address), port)
                synchronized(meshSockets) { meshSockets[peerId] = socket }
                emit(mapOf("type" to "connected", "peerId" to peerId, "direction" to "outgoing"))
                readMeshFrames(peerId, socket, emit)
            } catch (error: Exception) {
                emit(mapOf("type" to "transport_error", "peerId" to peerId, "message" to (error.message ?: "Mesh connection failed")))
            }
        }
    }

    fun sendTransport(peerId: String, bytes: ByteArray) {
        val socket = synchronized(meshSockets) { meshSockets[peerId] }
            ?: error("Mesh peer disconnected")
        synchronized(socket) {
            socket.getOutputStream().apply {
                write(ByteBuffer.allocate(4).putInt(bytes.size).array())
                write(bytes)
                flush()
            }
        }
    }

    fun disconnectTransport(peerId: String) {
        synchronized(meshSockets) { meshSockets.remove(peerId)?.close() }
    }

    private fun receiveMeshDiscovery(emit: (Map<String, Any?>) -> Unit) {
        val socket = meshDiscovery ?: return
        val buffer = ByteArray(4096)
        while (!socket.isClosed) {
            try {
                val packet = DatagramPacket(buffer, buffer.size)
                socket.receive(packet)
                val text = String(packet.data, 0, packet.length)
                val advertisement = meshAdvertisement
                if (text == DISCOVERY_REQUEST && advertisement != null) {
                    val response = beacon(advertisement)
                    socket.send(DatagramPacket(response, response.size, packet.address, packet.port))
                } else if (text.startsWith("$DISCOVERY_RESPONSE|")) {
                    val parts = text.split('|', limit = 4)
                    if (parts.size == 4) {
                        emit(mapOf(
                            "type" to "discovered",
                            "peerId" to "mesh:${parts[1]}",
                            "address" to parts[1],
                            "port" to parts[2].toIntOrNull(),
                            "advertisement" to android.util.Base64.decode(parts[3], android.util.Base64.DEFAULT),
                            "name" to "LIMS shop",
                        ))
                    }
                }
            } catch (_: Exception) { break }
        }
    }

    private fun beacon(advertisement: ByteArray): ByteArray {
        val address = requireNode().address.hostAddress
        return ("$DISCOVERY_RESPONSE|$address|$MESH_DATA_PORT|" +
            android.util.Base64.encodeToString(advertisement, android.util.Base64.NO_WRAP)).toByteArray()
    }

    private fun readMeshFrames(peerId: String, socket: Socket, emit: (Map<String, Any?>) -> Unit) {
        try {
            val input = socket.getInputStream()
            val header = ByteArray(4)
            while (!socket.isClosed) {
                readFully(input, header)
                val length = ByteBuffer.wrap(header).int
                if (length < 0 || length > MAX_FRAME_BYTES) break
                val frame = ByteArray(length)
                readFully(input, frame)
                emit(mapOf("type" to "frame", "peerId" to peerId, "bytes" to frame))
            }
        } catch (_: Exception) { }
        synchronized(meshSockets) { meshSockets.remove(peerId) }
        emit(mapOf("type" to "disconnected", "peerId" to peerId))
    }

    private fun readFully(input: java.io.InputStream, target: ByteArray) {
        var offset = 0
        while (offset < target.size) {
            val count = input.read(target, offset, target.size - offset)
            if (count < 0) error("Mesh socket closed")
            offset += count
        }
    }

    fun state(): Map<String, Any?> = latestState

    fun virtualNode(): AndroidVirtualNode = requireNode()

    fun close() {
        stopTransport()
        node?.close()
        node = null
        scope.cancel()
        meshExecutor.shutdownNow()
    }

    private fun requireNode(): AndroidVirtualNode =
        node ?: throw IllegalStateException("Custom mesh has not been started")

    companion object {
        // Virtual packet ports are decoded as signed shorts by Meshrabiya.
        private const val MESH_DISCOVERY_PORT = 29886
        private const val MESH_DATA_PORT = 29888
        private const val MAX_FRAME_BYTES = 1024 * 1024
        private const val DISCOVERY_REQUEST = "lims-lan-v1:discover"
        private const val DISCOVERY_RESPONSE = "lims-lan-v1"
    }

}
