package com.blackboxthc.overwatch.overwatch_app

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.wifi.WifiManager
import android.os.*
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import java.io.ByteArrayOutputStream

class ScreenCaptureService : Service() {

    companion object {
        const val ACTION_START = "com.blackboxthc.overwatch.START_CAPTURE"
        const val ACTION_STOP = "com.blackboxthc.overwatch.STOP_CAPTURE"
        const val EXTRA_RESULT_CODE = "EXTRA_RESULT_CODE"
        const val EXTRA_DATA = "EXTRA_DATA"
        private const val NOTIFICATION_ID = 9021
        private const val CHANNEL_ID = "overwatch_streaming_channel"

        var isRunning = false
            private set

        var realScreenWidth = 1080
            private set
        var realScreenHeight = 1920
            private set
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private var targetWidth = 540
    private var targetHeight = 1200
    private var screenDpi = 320

    private var lastFrameTime = 0L
    private val frameIntervalMs = 45L // ~22-25 FPS (Smooth real-time video)
    private var isScreenLocked = false

    // Reusable buffers to completely eliminate Android Garbage Collector (GC) jank & memory churn
    private var reusableRawBitmap: Bitmap? = null
    private var reusableCroppedBitmap: Bitmap? = null
    private val reusableOutputStream = ByteArrayOutputStream(64 * 1024)

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    // Smart lock pause: pause virtual display frame acquisition to preserve 100% battery
                    isScreenLocked = true
                }
                Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> {
                    // Smart unlock resume: instantly wake frame acquisition
                    isScreenLocked = false
                    lastFrameTime = 0L // force immediate capture on unlock
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Overwatch::ScreenCaptureLock")
        wakeLock?.acquire(24 * 60 * 60 * 1000L) // 24 hours max

        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Overwatch::WifiLock")
            wifiLock?.acquire()
        } catch (_: Exception) {}

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenStateReceiver, filter)

        backgroundThread = HandlerThread("OverwatchCaptureThread")
        backgroundThread?.start()
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_STICKY

        val action = intent.action
        if (action == ACTION_STOP) {
            stopCapture()
            stopSelf()
            return START_NOT_STICKY
        }

        if (action == ACTION_START) {
            val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
            val data = intent.getParcelableExtra<Intent>(EXTRA_DATA)

            if (resultCode == Activity.RESULT_OK && data != null) {
                startForegroundServiceNotification()
                startCapture(resultCode, data)
                isRunning = true
            } else {
                stopSelf()
            }
        }

        return START_STICKY
    }

    private fun startForegroundServiceNotification() {
        createNotificationChannel()

        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Overwatch Screen Broadcast")
            .setContentText("Screen stream is active in background")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Overwatch Streaming Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun startCapture(resultCode: Int, data: Intent) {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(metrics)

        realScreenWidth = metrics.widthPixels
        realScreenHeight = metrics.heightPixels
        screenDpi = metrics.densityDpi

        // Downscale to 540p width maintaining exact aspect ratio for ultra-fast, smooth 25 FPS encoding
        val scale = 540f / realScreenWidth.toFloat()
        targetWidth = 540
        targetHeight = ((realScreenHeight * scale).toInt() / 2) * 2

        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpManager.getMediaProjection(resultCode, data)

        imageReader = ImageReader.newInstance(
            targetWidth,
            targetHeight,
            PixelFormat.RGBA_8888,
            2
        )

        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stopCapture()
                stopSelf()
            }
        }, backgroundHandler)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "OverwatchVirtualDisplay",
            targetWidth,
            targetHeight,
            screenDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null,
            backgroundHandler
        )

        imageReader?.setOnImageAvailableListener({ reader ->
            // If screen is locked, skip processing completely
            if (isScreenLocked) {
                try {
                    reader.acquireLatestImage()?.close()
                } catch (_: Exception) {}
                return@setOnImageAvailableListener
            }

            val now = System.currentTimeMillis()
            if (now - lastFrameTime < frameIntervalMs) {
                try {
                    reader.acquireLatestImage()?.close()
                } catch (_: Exception) {}
                return@setOnImageAvailableListener
            }
            lastFrameTime = now

            var image: android.media.Image? = null
            try {
                image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * targetWidth
                val rawWidth = targetWidth + rowPadding / pixelStride

                if (reusableRawBitmap == null || reusableRawBitmap?.width != rawWidth || reusableRawBitmap?.height != targetHeight) {
                    reusableRawBitmap?.recycle()
                    reusableRawBitmap = Bitmap.createBitmap(rawWidth, targetHeight, Bitmap.Config.ARGB_8888)
                }
                reusableRawBitmap!!.copyPixelsFromBuffer(buffer)

                val finalBitmap = if (rowPadding != 0) {
                    if (reusableCroppedBitmap == null || reusableCroppedBitmap?.width != targetWidth || reusableCroppedBitmap?.height != targetHeight) {
                        reusableCroppedBitmap?.recycle()
                        reusableCroppedBitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
                    }
                    val canvas = android.graphics.Canvas(reusableCroppedBitmap!!)
                    canvas.drawBitmap(reusableRawBitmap!!, 0f, 0f, null)
                    reusableCroppedBitmap!!
                } else {
                    reusableRawBitmap!!
                }

                reusableOutputStream.reset()
                finalBitmap.compress(Bitmap.CompressFormat.JPEG, 50, reusableOutputStream)
                val jpegBytes = reusableOutputStream.toByteArray()

                FrameStreamHandler.sendFrame(jpegBytes, targetWidth, targetHeight)
            } catch (e: Exception) {
                // Ignore transient frame buffer errors
            } finally {
                image?.close()
            }
        }, backgroundHandler)
    }

    private fun stopCapture() {
        isRunning = false
        try {
            virtualDisplay?.release()
            virtualDisplay = null

            imageReader?.close()
            imageReader = null

            mediaProjection?.stop()
            mediaProjection = null

            reusableRawBitmap?.recycle()
            reusableRawBitmap = null
            reusableCroppedBitmap?.recycle()
            reusableCroppedBitmap = null
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(screenStateReceiver)
        } catch (_: Exception) {}

        stopCapture()

        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wifiLock?.let {
            if (it.isHeld) it.release()
        }

        backgroundThread?.quitSafely()
        super.onDestroy()
    }
}
