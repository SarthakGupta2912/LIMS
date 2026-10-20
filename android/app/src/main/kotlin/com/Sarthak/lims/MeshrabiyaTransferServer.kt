package com.Sarthak.lims

import android.content.Context
import android.net.Uri
import fi.iki.elonen.NanoHTTPD
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.io.FilterInputStream
import java.io.InputStream
import java.net.InetAddress
import java.net.URLEncoder
import java.util.concurrent.atomic.AtomicInteger

/** Meshrabiya test-app protocol: /send, /download/{id}, /decline/{id}, port 4242. */
class MeshrabiyaTransferServer(
    private val context: Context,
    private val client: OkHttpClient,
    private val address: InetAddress,
    private val receiveDir: File,
    private val changed: () -> Unit,
) : NanoHTTPD(4242) {
    private data class Transfer(
        val id: Int, val name: String, val host: String, val size: Long,
        val receivedAt: Long = System.currentTimeMillis(), val uri: Uri? = null,
        var status: String = "PENDING", var transferred: Long = 0,
        var transferTime: Long = 1, var file: String? = null,
    ) {
        fun map(): Map<String, Any?> = mapOf(
            "id" to id, "name" to name, "host" to host, "size" to size,
            "receivedAt" to receivedAt, "status" to status, "transferred" to transferred,
            "transferTime" to transferTime, "file" to file,
        )
    }
    private val ids = AtomicInteger()
    private val outgoing = mutableListOf<Transfer>()
    private val incoming = mutableListOf<Transfer>()
    private val lock = Any()

    init {
        receiveDir.mkdirs()
        receiveDir.listFiles { f -> f.name.endsWith(".rx.json") }?.forEach { f ->
            runCatching {
                val j = JSONObject(f.readText())
                incoming.add(Transfer(j.getInt("id"), j.getString("name"), j.getString("host"),
                    j.getLong("size"), j.getLong("receivedAt"), status = j.getString("status"),
                    transferred = j.getLong("transferred"), transferTime = j.getLong("transferTime"),
                    file = j.optString("file").takeIf { it != "null" && it.isNotEmpty() }))
            }
        }
        incoming.sortByDescending { it.receivedAt }
    }

    fun outgoingSnapshot() = synchronized(lock) { outgoing.map { it.map() } }
    fun incomingSnapshot() = synchronized(lock) { incoming.map { it.map() } }
    private fun update(block: () -> Unit) { synchronized(lock) { block() }; changed() }

    override fun serve(session: IHTTPSession): Response = try {
        when {
            session.uri == "/send" -> {
                val p = session.parameters
                val id = p["id"]?.firstOrNull()?.toIntOrNull() ?: error("Missing id")
                val name = p["filename"]?.firstOrNull() ?: error("Missing filename")
                val host = p["from"]?.firstOrNull() ?: error("Missing from")
                val size = p["size"]?.firstOrNull()?.toLongOrNull() ?: error("Missing size")
                update { incoming.add(0, Transfer(id, name, host, size)) }
                newFixedLengthResponse("OK")
            }
            session.uri.startsWith("/download/") -> {
                val id = session.uri.substringAfterLast('/').toInt()
                val transfer = synchronized(lock) { outgoing.first { it.id == id } }
                val input = context.contentResolver.openInputStream(requireNotNull(transfer.uri))
                    ?: error("Failed to open InputStream")
                update { transfer.status = "IN_PROGRESS" }
                val counted = object : FilterInputStream(input.buffered()) {
                    private var lastUpdate = 0L
                    override fun read(): Int = `in`.read().also { if (it >= 0) progress(1) }
                    override fun read(b: ByteArray, off: Int, len: Int): Int =
                        `in`.read(b, off, len).also { if (it > 0) progress(it) }
                    private fun progress(count: Int) {
                        synchronized(lock) { transfer.transferred += count }
                        if (System.currentTimeMillis() - lastUpdate > 500) {
                            lastUpdate = System.currentTimeMillis(); changed()
                        }
                    }
                    override fun close() {
                        super.close()
                        update { transfer.status = if (transfer.transferred == transfer.size) "COMPLETED" else "FAILED" }
                    }
                }
                newFixedLengthResponse(Response.Status.OK, "application/octet-stream", counted, transfer.size)
            }
            session.uri.startsWith("/decline/") -> {
                val id = session.uri.substringAfterLast('/').toInt()
                update { outgoing.first { it.id == id }.status = "DECLINED" }
                newFixedLengthResponse("OK")
            }
            else -> newFixedLengthResponse(Response.Status.NOT_FOUND, "text/plain", "not found: ${session.uri}")
        }
    } catch (e: Exception) {
        newFixedLengthResponse(Response.Status.BAD_REQUEST, "text/plain", e.message ?: "Bad request")
    }

    fun sendFile(uri: Uri, to: InetAddress) {
        val file = File(requireNotNull(uri.path))
        val transfer = Transfer(ids.incrementAndGet(), file.name, requireNotNull(to.hostAddress), file.length(), uri = uri)
        update { outgoing.add(0, transfer) }
        try {
            get("http://${to.hostAddress}:4242/send?id=${transfer.id}&filename=${URLEncoder.encode(transfer.name, "UTF-8")}&size=${transfer.size}&from=${address.hostAddress}")
        } catch (e: Exception) {
            update { transfer.status = "FAILED" }; throw e
        }
    }

    fun incomingAction(action: String, id: Int, host: String, receivedAt: Long) {
        val t = synchronized(lock) { incoming.first { it.id == id && it.host == host && it.receivedAt == receivedAt } }
        when (action) {
            "accept" -> {
                check(t.status == "PENDING")
                val dest = File(receiveDir, "${t.receivedAt}_${t.id}_${File(t.name).name}")
                val start = System.currentTimeMillis()
                update { t.status = "IN_PROGRESS" }
                try {
                    client.newCall(Request.Builder().url("http://${t.host}:4242/download/${t.id}").build()).execute().use { response ->
                        check(response.isSuccessful) { "Download failed: HTTP ${response.code}" }
                        val body = requireNotNull(response.body)
                        var lastUpdate = 0L
                        body.byteStream().use { input ->
                            dest.outputStream().use { output ->
                                val buffer = ByteArray(8192)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                    synchronized(lock) { t.transferred += count }
                                    if (System.currentTimeMillis() - lastUpdate > 500) {
                                        lastUpdate = System.currentTimeMillis(); changed()
                                    }
                                }
                            }
                        }
                        update {
                            t.transferTime = (System.currentTimeMillis() - start).coerceAtLeast(1)
                            t.file = dest.absolutePath
                            t.status = if (t.transferred == t.size) "COMPLETED" else "FAILED"
                        }
                    }
                } catch (e: Exception) {
                    update { t.status = "FAILED"; t.file = dest.absolutePath }
                }
                File(receiveDir, "${dest.name}.rx.json").writeText(JSONObject(t.map()).toString())
            }
            "decline" -> {
                check(t.status == "PENDING")
                runCatching { get("http://${t.host}:4242/decline/${t.id}") }
                update { t.status = "DECLINED" }
            }
            "delete" -> {
                check(t.status == "COMPLETED")
                t.file?.let { File(it).delete(); File("$it.rx.json").delete() }
                update { incoming.remove(t) }
            }
        }
    }

    private fun get(url: String) {
        client.newCall(Request.Builder().url(url).build()).execute().use {
            check(it.isSuccessful) { "Request failed: HTTP ${it.code}" }
            it.body?.string()
        }
    }
}
