// Owns WifiP2pManager discovery, group negotiation, and TCP peer channels.
package com.nankai.flutter_nearby_connections

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.util.Log
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.WpsInfo
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.ConnectException
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID
import kotlin.concurrent.thread

internal class WifiDirectSession(
    private val context: Context,
    private val flutter: MethodChannel,
    private var localName: String,
) {
    private val manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
    private val handler = Handler(context.mainLooper)
    private var channel = initializeChannel()
    private val localId = UUID.randomUUID().toString()
    private val peers = linkedMapOf<String, PeerRecord>()
    private val sockets = mutableMapOf<String, PeerSocket>()
    private var server: ServerSocket? = null
    private var advertising = false
    private var targetPeerId: String? = null
    private var groupFormed = false
    private var discovering = false
    private var closed = false
    private var advertisingGeneration = 0
    private var discoveryGeneration = 0
    private var p2pEnabled: Boolean? = null
    private var socketConnecting = false
    private var connectGeneration = 0

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            NearbyLog.info(TAG, "broadcast received action=${intent?.action}")
            when (intent?.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    val becameEnabled = p2pEnabled == false && enabled
                    p2pEnabled = enabled
                    NearbyLog.info(TAG, "Wi-Fi P2P state=${if (enabled) "enabled" else "disabled"}")
                    if (becameEnabled) {
                        if (advertising) startAdvertising(localName)
                        if (discovering) startDiscovery()
                    }
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    manager.requestPeers(channel) { list ->
                        NearbyLog.info(TAG, "peer list changed count=${list.deviceList.size}")
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    requestConnectionInfo()
                }
            }
        }
    }

    init {
        NearbyLog.info(TAG, "channel initialized channel=$channel")
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        NearbyLog.info(TAG, "receiver registered for state, peers, and connection changes")
        manager.setDnsSdResponseListeners(channel, { _, _, _ -> }, { _, record, device ->
            NearbyLog.info(TAG, "DNS-SD TXT record received device=${device.deviceAddress} record=$record")
            val id = record["id"] ?: return@setDnsSdResponseListeners
            val name = record["name"] ?: device.deviceName
            val state = peers[id]?.state ?: if (sockets.containsKey(id)) 2 else 0
            peers[id] = PeerRecord(id, name, device.deviceAddress, state)
            emitPeers()
        })
        requestConnectionInfo()
    }

    fun startAdvertising(name: String) {
        NearbyLog.info(TAG, "start advertising requested name=$name")
        if (name.isNotEmpty()) localName = name
        advertising = true
        val generation = ++advertisingGeneration
        val service = WifiP2pDnsSdServiceInfo.newInstance(
            "lims-invoice", "_presence._tcp", mapOf("id" to localId, "name" to localName),
        )
        // Local DNS-SD registration is independent of peer browsing. Starting
        // discoverPeers here made advertising fragile when the shop already
        // had a Wi-Fi Direct group or another operation was in progress.
        clearLocalServices(service, generation)
    }

    private fun clearLocalServices(service: WifiP2pDnsSdServiceInfo, generation: Int, attempt: Int = 0) {
        if (!advertising || generation != advertisingGeneration) return
        manager.clearLocalServices(channel, action(
            onSuccess = {
                if (!advertising || generation != advertisingGeneration) return@action
                NearbyLog.info(TAG, "local services cleared")
                manager.addLocalService(channel, service, action(
                    onSuccess = { NearbyLog.info(TAG, "local service registration succeeded") },
                    onFailure = {
                        if (retryBusy("add local service", it, attempt) { clearLocalServices(service, generation, attempt + 1) }) return@action
                        if (retryOperation("add local service", generation, attempt) {
                            clearLocalServices(service, generation, attempt + 1)
                        }) return@action
                        Log.e(TAG, "local service registration failed reason=$it")
                    },
                ))
            },
            onFailure = {
                if (retryBusy("clear local services", it, attempt) { clearLocalServices(service, generation, attempt + 1) }) return@action
                if (retryOperation("clear local services", generation, attempt) {
                    clearLocalServices(service, generation, attempt + 1)
                }) return@action
                Log.e(TAG, "clear local services failed reason=$it")
            },
        ))
    }

    fun stopAdvertising() {
        advertising = false
        advertisingGeneration++
        manager.clearLocalServices(channel, action())
    }

    fun startDiscovery() {
        discovering = true
        val generation = ++discoveryGeneration
        NearbyLog.info(TAG, "discovery sequence started")
        val start = {
            activatePeerDiscovery("service discovery", isCurrent = {
                discovering && generation == discoveryGeneration
            }) { clearServiceRequests(generation) }
        }
        // Android can retain a Wi-Fi Direct group after an app update or a
        // force-stop. A fresh customer discovery must release that stale group
        // first, otherwise discoverPeers commonly returns BUSY or finds no DNS
        // records. Active sockets are preserved for normal reconnects.
        if (groupFormed && sockets.isEmpty()) {
            NearbyLog.info(TAG, "releasing stale Wi-Fi Direct group before discovery")
            manager.removeGroup(channel, action(
                onSuccess = {
                    groupFormed = false
                    handler.postDelayed(start, 400L)
                },
                onFailure = {
                    groupFormed = false
                    handler.postDelayed(start, 700L)
                },
            ))
        } else {
            start()
        }
    }

    private fun activatePeerDiscovery(
        label: String,
        attempt: Int = 0,
        isCurrent: () -> Boolean,
        onReady: () -> Unit,
    ) {
        if (!isCurrent()) return
        NearbyLog.info(TAG, "discoverPeers bootstrap started for $label")
        manager.discoverPeers(channel, action(
            onSuccess = {
                if (!isCurrent()) return@action
                NearbyLog.info(TAG, "discoverPeers bootstrap succeeded for $label")
                onReady()
            },
            onFailure = {
                if (retryBusy("discoverPeers bootstrap for $label", it, attempt) {
                    activatePeerDiscovery(label, attempt + 1, isCurrent, onReady)
                }) return@action
                Log.e(TAG, "discoverPeers bootstrap failed for $label reason=$it")
            },
        ))
    }

    private fun clearServiceRequests(generation: Int, attempt: Int = 0) {
        if (!discovering || generation != discoveryGeneration) return
        manager.clearServiceRequests(channel, action(
            onSuccess = {
                if (!discovering || generation != discoveryGeneration) return@action
                NearbyLog.info(TAG, "service requests cleared")
                manager.addServiceRequest(channel, android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest.newInstance(), action(
                    onSuccess = {
                        if (!discovering || generation != discoveryGeneration) return@action
                        NearbyLog.info(TAG, "service request added; invoking discoverServices")
                        manager.discoverServices(channel, action(
                            onSuccess = { NearbyLog.info(TAG, "discoverServices succeeded") },
                            onFailure = {
                                if (retryBusy("discoverServices", it, attempt) { clearServiceRequests(generation, attempt + 1) }) return@action
                                if (retryOperation("discoverServices", generation, attempt) {
                                    clearServiceRequests(generation, attempt + 1)
                                }) return@action
                                Log.e(TAG, "discoverServices failed reason=$it")
                            },
                        ))
                    },
                    onFailure = {
                        if (retryBusy("add service request", it, attempt) { clearServiceRequests(generation, attempt + 1) }) return@action
                        if (retryOperation("add service request", generation, attempt) {
                            clearServiceRequests(generation, attempt + 1)
                        }) return@action
                        Log.e(TAG, "add service request failed reason=$it")
                    },
                ))
            },
            onFailure = {
                if (retryBusy("clear service requests", it, attempt) { clearServiceRequests(generation, attempt + 1) }) return@action
                if (retryOperation("clear service requests", generation, attempt) {
                    clearServiceRequests(generation, attempt + 1)
                }) return@action
                Log.e(TAG, "clear service requests failed reason=$it")
            },
        ))
    }

    fun stopDiscovery() {
        discovering = false
        discoveryGeneration++
        manager.stopPeerDiscovery(channel, action())
    }

    fun connect(peerId: String) {
        val peer = peers[peerId] ?: error("Unknown Wi-Fi Direct peer $peerId")
        NearbyLog.info(TAG, "connect requested peerId=$peerId address=${peer.address}")
        if (peer.address.isBlank()) error("Wi-Fi Direct peer address is unavailable")
        targetPeerId = peerId
        peer.state = 1
        emitPeers()
        val generation = ++connectGeneration
        if (groupFormed) {
            NearbyLog.info(TAG, "reusing existing Wi-Fi Direct group for peerId=$peerId")
            requestConnectionInfo()
            return
        }
        negotiate(peerId, generation)
    }

    private fun negotiate(peerId: String, generation: Int, attempt: Int = 0) {
        if (closed || generation != connectGeneration || targetPeerId != peerId) return
        val peer = peers[peerId] ?: return
        val config = WifiP2pConfig().apply {
            deviceAddress = peer.address
            wps.setup = WpsInfo.PBC
            // Customers initiate the request, but the shop must remain the
            // group owner because it hosts the multi-customer TCP server.
            groupOwnerIntent = 0
        }
        manager.connect(channel, config, action(
            onSuccess = { NearbyLog.info(TAG, "connect negotiation accepted peerId=$peerId") },
            onFailure = {
                Log.e(TAG, "connect negotiation failed peerId=$peerId reason=$it")
                if (attempt < MAX_CONNECT_RETRIES && generation == connectGeneration && !closed) {
                    val delay = 600L * (attempt + 1)
                    Log.w(TAG, "retrying connect peerId=$peerId retry=${attempt + 1} delayMs=$delay")
                    manager.cancelConnect(channel, action(
                        onSuccess = { handler.postDelayed({ negotiate(peerId, generation, attempt + 1) }, delay) },
                        onFailure = { handler.postDelayed({ negotiate(peerId, generation, attempt + 1) }, delay) },
                    ))
                } else {
                    disconnected(peerId)
                }
            },
        ))
    }

    fun disconnect(peerId: String) {
        connectGeneration++
        if (targetPeerId == peerId) targetPeerId = null
        manager.cancelConnect(channel, action())
        sockets.remove(peerId)?.close()
        disconnected(peerId)
        if (sockets.isEmpty()) removeGroup()
    }

    fun send(peerId: String, message: String) =
        (sockets[peerId] ?: error("Peer $peerId is not connected")).send(message)

    private fun startServer() {
        if (server != null) return
        server = ServerSocket().apply {
            reuseAddress = true
            bind(InetSocketAddress(PORT))
        }
        NearbyLog.info(TAG, "TCP server listening port=$PORT")
        thread(name = "lims-wifi-server", isDaemon = true) {
            while (server?.isClosed == false) {
                try {
                    attach(server!!.accept(), null)
                } catch (error: Exception) {
                    if (server?.isClosed == false) {
                        Log.e(TAG, "incoming customer socket failed", error)
                    }
                }
            }
        }
    }

    private fun requestConnectionInfo() {
        manager.requestConnectionInfo(channel) { info ->
            groupFormed = info.groupFormed
            NearbyLog.info(TAG, "connection info groupFormed=${info.groupFormed} owner=${info.isGroupOwner} address=${info.groupOwnerAddress}")
            if (!groupFormed) {
                // A customer leaving can tear down the P2P group while the
                // local DNS-SD registration remains stale. Release the old
                // server and re-register the shop advertisement afterwards.
                sockets.values.forEach(PeerSocket::close)
                sockets.clear()
                server?.close()
                server = null
                if (advertising && !closed) {
                    handler.postDelayed({
                        if (advertising && !closed && !groupFormed) {
                            startAdvertising(localName)
                        }
                    }, 750L)
                }
                return@requestConnectionInfo
            }
            if (info.isGroupOwner) {
                startServer()
            } else {
                server?.close()
                server = null
                info.groupOwnerAddress?.hostAddress?.let(::connectSocket)
            }
        }
    }

    private fun connectSocket(host: String, attempt: Int = 0) {
        if (socketConnecting || sockets.isNotEmpty() || closed) return
        socketConnecting = true
        thread(name = "lims-wifi-connect", isDaemon = true) {
        NearbyLog.info(TAG, "TCP client connecting host=$host port=$PORT")
        runCatching {
            val socket = Socket()
            socket.connect(InetSocketAddress(host, PORT), 15_000)
            attach(socket, targetPeerId)
        }.onFailure {
            socketConnecting = false
            if (it is ConnectException && groupFormed && attempt < MAX_SOCKET_RETRIES && !closed) {
                val delay = 500L * (attempt + 1)
                Log.w(TAG, "TCP server not ready; retry=${attempt + 1} delayMs=$delay")
                handler.postDelayed({ connectSocket(host, attempt + 1) }, delay)
                return@onFailure
            }
            Log.e(TAG, "TCP client connection failed host=$host", it)
            targetPeerId?.let(::disconnected)
        }
        }
    }

    private fun attach(socket: Socket, expectedId: String?) {
        PeerSocket(socket, localId, localName, expectedId, ::ready, ::message, ::disconnected).start()
    }

    private fun ready(peerId: String, name: String, socket: PeerSocket) {
        socketConnecting = false
        connectGeneration++
        NearbyLog.info(TAG, "TCP peer ready peerId=$peerId name=$name")
        val record = peers[peerId] ?: PeerRecord(peerId, name, "", 2)
        record.state = 2
        peers[peerId] = record
        sockets.put(peerId, socket)?.close()
        emitPeers()
    }

    private fun message(peerId: String, value: String) = context.runOnMain {
        flutter.invokeMethod("invoke_message_receive_method", mapOf("deviceId" to peerId, "message" to value))
    }

    private fun disconnected(peerId: String) {
        sockets.remove(peerId)?.close()
        peers[peerId]?.state = 0
        emitPeers()
    }

    private fun emitPeers() = context.runOnMain {
        val array = JSONArray()
        peers.values.forEach { array.put(JSONObject().put("deviceId", it.id).put("deviceName", it.name).put("state", it.state)) }
        flutter.invokeMethod("invoke_change_state_method", array.toString())
    }

    fun close() {
        closed = true
        runCatching { context.unregisterReceiver(receiver) }
        sockets.values.forEach(PeerSocket::close)
        sockets.clear()
        runCatching { server?.close() }
        manager.stopPeerDiscovery(channel, action())
        manager.clearLocalServices(channel, action())
        manager.clearServiceRequests(channel, action())
        removeGroup()
    }

    private fun initializeChannel(): WifiP2pManager.Channel {
        val initialized = manager.initialize(context, context.mainLooper) {
            Log.e(TAG, "WifiP2pManager channel disconnected; reinitializing")
            if (!closed) {
                channel = initializeChannel()
                if (advertising) startAdvertising(localName)
                if (discovering) startDiscovery()
            }
        }
        NearbyLog.info(TAG, "channel initialized channel=$initialized")
        return initialized
    }

    private fun retryBusy(label: String, reason: Int, attempt: Int, retry: () -> Unit): Boolean {
        if (reason != WifiP2pManager.BUSY || attempt >= MAX_BUSY_RETRIES || closed) return false
        val delay = 500L * (attempt + 1)
        Log.w(TAG, "$label busy; retry=${attempt + 1} delayMs=$delay")
        handler.postDelayed(retry, delay)
        return true
    }

    private fun retryOperation(
        label: String,
        generation: Int,
        attempt: Int,
        retry: () -> Unit,
    ): Boolean {
        if (attempt >= MAX_OPERATION_RETRIES || closed) return false
        val delay = 750L * (attempt + 1)
        NearbyLog.info(TAG, "$label failed; retry=${attempt + 1} delayMs=$delay generation=$generation")
        handler.postDelayed(retry, delay)
        return true
    }

    private fun removeGroup() {
        if (!groupFormed) return
        manager.removeGroup(channel, action(
            onSuccess = { groupFormed = false },
            onFailure = { groupFormed = false },
        ))
    }

    private fun action(
        onSuccess: () -> Unit = {},
        onFailure: (Int) -> Unit = {},
    ) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() = onSuccess()
        override fun onFailure(reason: Int) = onFailure(reason)
    }

    private data class PeerRecord(val id: String, val name: String, val address: String, var state: Int)
    companion object {
        private const val PORT = 39887
        private const val TAG = "LimsWifiDirect"
        private const val MAX_BUSY_RETRIES = 4
        private const val MAX_OPERATION_RETRIES = 4
        private const val MAX_CONNECT_RETRIES = 3
        private const val MAX_SOCKET_RETRIES = 6
    }
}

private fun Context.runOnMain(block: () -> Unit) =
    android.os.Handler(mainLooper).post(block)
