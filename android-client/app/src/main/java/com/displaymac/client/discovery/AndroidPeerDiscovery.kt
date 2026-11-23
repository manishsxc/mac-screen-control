package com.displaymac.client.discovery

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.security.SecureRandom

data class DiscoveryBeacon(
    val code: String,
    val role: String,
    val deviceName: String,
    val platform: String,
    val port: Int = 7100
)

class AndroidPeerDiscovery(private val context: Context) {
    companion object {
        private const val TAG = "PeerDiscovery"
        const val DISCOVERY_PORT = 7105
        const val BROADCAST_ADDRESS = "255.255.255.255"

        fun generate6DigitCode(): String {
            val random = SecureRandom()
            val code = 100000 + random.nextInt(900000)
            return code.toString()
        }
    }

    private var scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var isRunning = false
    private var multicastLock: WifiManager.MulticastLock? = null

    var onPeerDiscovered: ((beacon: DiscoveryBeacon, ip: String) -> Unit)? = null

    fun startAdvertising(beacon: DiscoveryBeacon) {
        stop()
        isRunning = true
        acquireMulticastLock()

        // 1. Broadcast coroutine
        scope.launch {
            val json = JSONObject().apply {
                put("code", beacon.code)
                put("role", beacon.role)
                put("deviceName", beacon.deviceName)
                put("platform", beacon.platform)
                put("port", beacon.port)
                put("timestamp", System.currentTimeMillis() / 1000.0)
            }.toString()

            val bytes = json.toByteArray(Charsets.UTF_8)
            var socket: DatagramSocket? = null
            try {
                socket = DatagramSocket()
                socket.broadcast = true
                val address = InetAddress.getByName(BROADCAST_ADDRESS)
                val packet = DatagramPacket(bytes, bytes.size, address, DISCOVERY_PORT)

                while (isRunning && isActive) {
                    socket.send(packet)
                    delay(1000)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Broadcast send error: ${e.message}")
            } finally {
                socket?.close()
            }
        }

        // 2. Also listen in background
        startListeningInternal()
    }

    fun startListeningForCode(targetCode: String, onMatched: (ip: String, port: Int) -> Unit) {
        stop()
        isRunning = true
        acquireMulticastLock()

        startListeningInternal { beacon, ip ->
            if (beacon.code == targetCode) {
                onMatched(ip, beacon.port)
            }
        }
    }

    private fun startListeningInternal(customFilter: ((DiscoveryBeacon, String) -> Unit)? = null) {
        scope.launch {
            var socket: DatagramSocket? = null
            try {
                socket = DatagramSocket(DISCOVERY_PORT)
                socket.broadcast = true
                val buffer = ByteArray(2048)

                while (isRunning && isActive) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    socket.receive(packet)
                    val senderIp = packet.address.hostAddress ?: continue
                    val text = String(packet.data, 0, packet.length, Charsets.UTF_8)

                    try {
                        val obj = JSONObject(text)
                        val beacon = DiscoveryBeacon(
                            code = obj.getString("code"),
                            role = obj.optString("role", "sharer"),
                            deviceName = obj.optString("deviceName", "Unknown"),
                            platform = obj.optString("platform", "unknown"),
                            port = obj.optInt("port", 7100)
                        )
                        customFilter?.invoke(beacon, senderIp)
                        onPeerDiscovered?.invoke(beacon, senderIp)
                    } catch (e: Exception) {
                        // ignore malformed packets
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Discovery receive error: ${e.message}")
            } finally {
                socket?.close()
            }
        }
    }

    fun stop() {
        isRunning = false
        scope.cancel()
        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        releaseMulticastLock()
    }

    private fun acquireMulticastLock() {
        try {
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifi?.createMulticastLock("DisplayMacMulticast")?.apply {
                setReferenceCounted(true)
                acquire()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire multicast lock: ${e.message}")
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.let {
                if (it.isHeld) it.release()
            }
            multicastLock = null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to release multicast lock: ${e.message}")
        }
    }
}
