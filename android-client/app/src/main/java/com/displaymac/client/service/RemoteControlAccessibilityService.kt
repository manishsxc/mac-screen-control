package com.displaymac.client.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class RemoteControlAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "RemoteAccessibility"
        var instance: RemoteControlAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "RemoteControlAccessibilityService connected and ready for touch injection.")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op: only used for gesture injection
    }

    override fun onInterrupt() {
        Log.w(TAG, "RemoteControlAccessibilityService interrupted.")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) {
            instance = null
        }
    }

    /**
     * Injects a tap gesture at normalized coordinates (0.0 - 1.0)
     */
    fun injectTap(normX: Float, normY: Float) {
        val displayMetrics = resources.displayMetrics
        val screenX = normX * displayMetrics.widthPixels
        val screenY = normY * displayMetrics.heightPixels

        val path = Path().apply {
            moveTo(screenX, screenY)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()

        dispatchGesture(gesture, null, null)
    }

    /**
     * Injects a swipe/drag gesture
     */
    fun injectSwipe(startX: Float, startY: Float, endX: Float, endY: Float, durationMs: Long = 200) {
        val displayMetrics = resources.displayMetrics
        val path = Path().apply {
            moveTo(startX * displayMetrics.widthPixels, startY * displayMetrics.heightPixels)
            lineTo(endX * displayMetrics.widthPixels, endY * displayMetrics.heightPixels)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()

        dispatchGesture(gesture, null, null)
    }
}
