package com.blackboxthc.overwatch.overwatch_app

import android.accessibilityservice.AccessibilityService
import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val REQUEST_MEDIA_PROJECTION = 1001
        private const val REQUEST_DEVICE_ADMIN = 1002
        private const val METHOD_CHANNEL = "com.blackboxthc.overwatch/screen_capture"
        private const val EVENT_CHANNEL = "com.blackboxthc.overwatch/screen_frames"
    }

    private var pendingCaptureResult: MethodChannel.Result? = null

    // Touch gesture tracking state to cleanly separate Click from Drag/Swipe
    private var isMouseDown = false
    private var isDragging = false
    private var touchDownX = 0f
    private var touchDownY = 0f
    private var touchDownTime = 0L
    private var currentTouchX = 0f
    private var currentTouchY = 0f
    private var touchButton = "left"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register EventChannel for frame streaming
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(FrameStreamHandler)

        val adminComponent = ComponentName(this, OverwatchDeviceAdminReceiver::class.java)

        // Register MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestScreenCapture" -> {
                        if (ScreenCaptureService.isRunning) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        pendingCaptureResult = result
                        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        startActivityForResult(mpManager.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
                    }
                    "stopScreenCapture" -> {
                        val stopIntent = Intent(this, ScreenCaptureService::class.java).apply {
                            action = ScreenCaptureService.ACTION_STOP
                        }
                        startService(stopIntent)
                        result.success(true)
                    }
                    "isCapturing" -> {
                        result.success(ScreenCaptureService.isRunning)
                    }
                    "requestBatteryOptimization" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                                val packageName = packageName
                                if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                        data = Uri.parse("package:$packageName")
                                    }
                                    startActivity(intent)
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("BATTERY_ERROR", e.message, null)
                        }
                    }
                    "isDeviceAdminActive" -> {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        result.success(dpm.isAdminActive(adminComponent))
                    }
                    "requestDeviceAdmin" -> {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                            putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "Enables device administrator to prevent Overwatch from being accidentally uninstalled or killed."
                            )
                        }
                        startActivityForResult(intent, REQUEST_DEVICE_ADMIN)
                        result.success(true)
                    }
                    "deactivateDeviceAdmin" -> {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        if (dpm.isAdminActive(adminComponent)) {
                            dpm.removeActiveAdmin(adminComponent)
                        }
                        result.success(true)
                    }
                    "isAccessibilityActive" -> {
                        result.success(OverwatchAccessibilityService.isServiceActive)
                    }
                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    }
                    "injectRemoteInput" -> {
                        val eventType = call.argument<String>("event_type") ?: ""
                        val params = call.argument<Map<String, Any>>("params") ?: emptyMap()

                        val screenW = ScreenCaptureService.realScreenWidth.toFloat()
                        val screenH = ScreenCaptureService.realScreenHeight.toFloat()

                        when (eventType) {
                            "mouse_click" -> {
                                val pressed = (params["pressed"] as? Boolean) ?: true
                                val normX = (params["x"] as? Number)?.toFloat() ?: 0.5f
                                val normY = (params["y"] as? Number)?.toFloat() ?: 0.5f
                                val button = params["button"] as? String ?: "left"

                                val absX = (normX * screenW).coerceIn(0f, screenW)
                                val absY = (normY * screenH).coerceIn(0f, screenH)

                                if (pressed) {
                                    // Touch DOWN: start tracking gesture, DO NOT tap immediately
                                    isMouseDown = true
                                    isDragging = false
                                    touchDownX = absX
                                    touchDownY = absY
                                    currentTouchX = absX
                                    currentTouchY = absY
                                    touchDownTime = System.currentTimeMillis()
                                    touchButton = button
                                    result.success(true)
                                } else {
                                    // Touch UP: evaluate whether it was a TAP or a SWIPE/DRAG
                                    isMouseDown = false
                                    val duration = (System.currentTimeMillis() - touchDownTime).coerceAtLeast(30)
                                    val ok = if (!isDragging) {
                                        // User clicked and released without dragging!
                                        if (touchButton == "right" || duration > 450) {
                                            OverwatchAccessibilityService.dispatchLongClick(touchDownX, touchDownY)
                                        } else {
                                            OverwatchAccessibilityService.dispatchClick(touchDownX, touchDownY)
                                        }
                                    } else {
                                        // User dragged! Execute swipe gesture smoothly
                                        OverwatchAccessibilityService.dispatchSwipe(touchDownX, touchDownY, absX, absY, duration.coerceIn(80, 400))
                                    }
                                    result.success(ok)
                                }
                            }
                            "mouse_move" -> {
                                val normX = (params["x"] as? Number)?.toFloat() ?: 0.5f
                                val normY = (params["y"] as? Number)?.toFloat() ?: 0.5f
                                val absX = (normX * screenW).coerceIn(0f, screenW)
                                val absY = (normY * screenH).coerceIn(0f, screenH)

                                currentTouchX = absX
                                currentTouchY = absY

                                if (isMouseDown) {
                                    val dist = Math.hypot((absX - touchDownX).toDouble(), (absY - touchDownY).toDouble()).toFloat()
                                    // If moved more than 20 pixels, classify as a drag gesture
                                    if (dist > 20f) {
                                        isDragging = true
                                    }
                                }
                                result.success(true)
                            }
                            "mouse_scroll" -> {
                                val normX = (params["x"] as? Number)?.toFloat() ?: 0.5f
                                val normY = (params["y"] as? Number)?.toFloat() ?: 0.5f
                                val curX = (normX * screenW).coerceIn(0f, screenW)
                                val curY = (normY * screenH).coerceIn(0f, screenH)

                                val deltaY = (params["dy"] as? Number)?.toFloat() ?: 0f
                                if (deltaY != 0f) {
                                    // Natural mobile scroll:
                                    // Rolling wheel DOWN (deltaY < 0) means content moves down (finger swipes UP)
                                    // Rolling wheel UP (deltaY > 0) means content moves up (finger swipes DOWN)
                                    val swipeDistance = 450f
                                    val endY = if (deltaY < 0) {
                                        (curY - swipeDistance).coerceIn(50f, screenH - 50f)
                                    } else {
                                        (curY + swipeDistance).coerceIn(50f, screenH - 50f)
                                    }
                                    val ok = OverwatchAccessibilityService.dispatchSwipe(curX, curY, curX, endY, 160)
                                    result.success(ok)
                                } else {
                                    result.success(true)
                                }
                            }
                            "key_press" -> {
                                val key = params["key"] as? String ?: ""
                                if (key.equals("back", ignoreCase = true) || key.equals("esc", ignoreCase = true)) {
                                    OverwatchAccessibilityService.performGlobal(AccessibilityService.GLOBAL_ACTION_BACK)
                                } else if (key.equals("home", ignoreCase = true) || key.equals("win", ignoreCase = true)) {
                                    OverwatchAccessibilityService.performGlobal(AccessibilityService.GLOBAL_ACTION_HOME)
                                }
                                result.success(true)
                            }
                            "global_action" -> {
                                val actionStr = params["action"] as? String ?: "back"
                                val actionCode = when (actionStr.lowercase()) {
                                    "home" -> AccessibilityService.GLOBAL_ACTION_HOME
                                    "recents" -> AccessibilityService.GLOBAL_ACTION_RECENTS
                                    "notifications" -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
                                    else -> AccessibilityService.GLOBAL_ACTION_BACK
                                }
                                val ok = OverwatchAccessibilityService.performGlobal(actionCode)
                                result.success(ok)
                            }
                            else -> result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START
                    putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenCaptureService.EXTRA_DATA, data)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }

                pendingCaptureResult?.success(true)
            } else {
                pendingCaptureResult?.error("DENIED", "Media projection permission denied by user", null)
            }
            pendingCaptureResult = null
        }
    }
}
