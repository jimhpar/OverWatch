package com.blackboxthc.overwatch.overwatch_app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object FrameStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun sendFrame(bytes: ByteArray, width: Int, height: Int) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                val data = HashMap<String, Any>()
                data["frame"] = bytes
                data["width"] = width
                data["height"] = height
                sink.success(data)
            } catch (e: Exception) {
                // Ignore transient channel errors
            }
        }
    }
}
