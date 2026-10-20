// Owns one length-prefixed TCP channel negotiated over a Wi-Fi Direct group.
package com.nankai.flutter_nearby_connections

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import android.util.Log
import kotlin.concurrent.thread

internal class PeerSocket(
    private val socket: Socket,
    private val localId: String,
    private val localName: String,
    private val expectedPeerId: String?,
    private val onReady: (String, String, PeerSocket) -> Unit,
    private val onMessage: (String, String) -> Unit,
    private val onClosed: (String) -> Unit,
) {
    private val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
    private val output = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
    private val writer = Executors.newSingleThreadExecutor { task ->
        Thread(task, "lims-wifi-writer").apply { isDaemon = true }
    }
    @Volatile private var peerId: String? = expectedPeerId
    @Volatile private var closed = false

    fun start() = thread(name = "lims-wifi-peer", isDaemon = true) {
        try {
            writePacket("$localId\n$localName")
            val handshake = readPacket().split('\n', limit = 2)
            val remoteId = expectedPeerId ?: handshake.first()
            peerId = remoteId
            onReady(remoteId, handshake.getOrElse(1) { "Nearby device" }, this)
            while (!closed) onMessage(remoteId, readPacket())
        } catch (error: Exception) {
            Log.e(TAG, "peer channel failed peerId=$peerId", error)
            peerId?.let(onClosed)
            close()
        }
    }

    fun send(message: String) {
        check(!closed) { "Peer socket is closed" }
        val bytes = message.toByteArray(StandardCharsets.UTF_8)
        require(bytes.size <= MAX_PACKET_BYTES) { "Message is too large" }
        writer.execute {
            try {
                writePacket(bytes)
            } catch (error: Exception) {
                Log.e(TAG, "peer send failed peerId=$peerId", error)
                peerId?.let(onClosed)
                close()
            }
        }
    }

    @Synchronized
    private fun writePacket(message: String) {
        val bytes = message.toByteArray(StandardCharsets.UTF_8)
        require(bytes.size <= MAX_PACKET_BYTES) { "Message is too large" }
        writePacket(bytes)
    }

    @Synchronized
    private fun writePacket(bytes: ByteArray) {
        output.writeInt(bytes.size)
        output.write(bytes)
        output.flush()
    }

    private fun readPacket(): String {
        val length = input.readInt()
        require(length in 0..MAX_PACKET_BYTES) { "Invalid message length" }
        val bytes = ByteArray(length)
        input.readFully(bytes)
        return String(bytes, StandardCharsets.UTF_8)
    }

    fun close() {
        if (closed) return
        closed = true
        writer.shutdownNow()
        runCatching { socket.close() }
    }

    companion object {
        private const val MAX_PACKET_BYTES = 1 shl 20
        private const val TAG = "LimsWifiDirect"
    }
}
