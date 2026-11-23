package com.displaymac.client.capture

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer

class AndroidScreenCaptureService(
    private val context: Context,
    private val mediaProjection: MediaProjection,
    private val width: Int = 1920,
    private val height: Int = 1080,
    private val dpi: Int = 320,
    private val targetFps: Int = 60
) {
    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_HEVC
        private const val BIT_RATE = 15_000_000 // 15 Mbps
        private const val I_FRAME_INTERVAL = 1
    }

    private var mediaCodec: MediaCodec? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null
    private var isStreaming = false

    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var outputStream: OutputStream? = null

    fun startStreaming(port: Int = 7101) {
        if (isStreaming) return
        isStreaming = true

        handlerThread = HandlerThread("MediaCodecThread").apply { start() }
        handler = Handler(handlerThread!!.looper)

        Thread {
            try {
                serverSocket = ServerSocket(port)
                Log.i(TAG, "Screen streamer listening on port $port")
                clientSocket = serverSocket!!.accept()
                outputStream = clientSocket!!.getOutputStream()
                setupCodec()
            } catch (e: Exception) {
                Log.e(TAG, "Streaming socket error: ${e.message}")
            }
        }.start()
    }

    private fun setupCodec() {
        try {
            val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
                setInteger(MediaFormat.KEY_FRAME_RATE, targetFps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL)
            }

            mediaCodec = MediaCodec.createEncoderByType(MIME_TYPE)
            mediaCodec!!.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val inputSurface = mediaCodec!!.createInputSurface()

            virtualDisplay = mediaProjection.createVirtualDisplay(
                "DisplayMacProjection",
                width,
                height,
                dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                inputSurface,
                null,
                handler
            )

            mediaCodec!!.setCallback(object : MediaCodec.Callback() {
                override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {}

                override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                    val buffer = codec.getOutputBuffer(index) ?: return
                    if (info.size > 0 && outputStream != null) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val outData = ByteArray(info.size)
                        buffer.get(outData)
                        try {
                            outputStream?.write(outData)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error writing video frame: ${e.message}")
                        }
                    }
                    codec.releaseOutputBuffer(index, false)
                }

                override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
                    Log.e(TAG, "MediaCodec error: ${e.message}")
                }

                override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
                    Log.i(TAG, "Output format changed: $format")
                }
            }, handler)

            mediaCodec!!.start()
            Log.i(TAG, "Screen encoder started at ${width}x${height} @ ${targetFps}fps")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to setup screen encoder: ${e.message}")
        }
    }

    fun stop() {
        isStreaming = false
        try {
            mediaCodec?.stop()
            mediaCodec?.release()
            mediaCodec = null

            virtualDisplay?.release()
            virtualDisplay = null

            mediaProjection.stop()

            outputStream?.close()
            clientSocket?.close()
            serverSocket?.close()

            handlerThread?.quitSafely()
            handlerThread = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping capture service: ${e.message}")
        }
    }
}
