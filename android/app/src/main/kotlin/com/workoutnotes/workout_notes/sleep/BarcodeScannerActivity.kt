package com.workoutnotes.workout_notes.sleep

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.CountDownTimer
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class BarcodeScannerActivity : ComponentActivity() {
    companion object {
        const val EXTRA_ENROLLMENT = "barcode_enrollment"
        const val EXTRA_RAW_VALUE = "barcode_raw_value"
        const val EXTRA_FORMAT = "barcode_format"
        const val EXTRA_CAMERA_DENIED = "barcode_camera_denied"
        const val EXTRA_TIMEOUT = "barcode_timeout"
        const val EXTRA_TIMEOUT_MILLIS = "barcode_timeout_millis"
        const val RESULT_CANCELLED = 0
        const val RESULT_SUCCESS = 1
        private const val CAMERA_REQUEST = 7654
    }

    private lateinit var previewView: PreviewView
    private lateinit var cameraExecutor: ExecutorService
    private lateinit var scanner: BarcodeScanner
    private var camera: androidx.camera.core.Camera? = null
    private lateinit var torchButton: Button
    private lateinit var timerView: TextView
    private var timer: CountDownTimer? = null
    private var lastValue: String? = null
    private var stableReads = 0
    private var completed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cameraExecutor = Executors.newSingleThreadExecutor()
        scanner = BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(
                    Barcode.FORMAT_EAN_8,
                    Barcode.FORMAT_EAN_13,
                    Barcode.FORMAT_UPC_A,
                    Barcode.FORMAT_UPC_E,
                    Barcode.FORMAT_CODE_128,
                    Barcode.FORMAT_CODE_39,
                    Barcode.FORMAT_CODE_93,
                    Barcode.FORMAT_CODABAR,
                    Barcode.FORMAT_ITF,
                    Barcode.FORMAT_QR_CODE,
                )
                .build(),
        )
        render()
        startTimeoutTimer()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_REQUEST,
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_REQUEST &&
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        ) {
            startCamera()
        } else if (requestCode == CAMERA_REQUEST) {
            setResult(RESULT_CANCELED, Intent().putExtra(EXTRA_CAMERA_DENIED, true))
            finish()
        }
    }

    private fun render() {
        previewView = PreviewView(this).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        root.addView(previewView, FrameLayout.LayoutParams(-1, -1))
        root.addView(TextView(this).apply {
            text = getString(com.workoutnotes.workout_notes.R.string.barcode_scanner_instruction)
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(32, 24, 32, 24)
            setBackgroundColor(0x99000000.toInt())
        }, FrameLayout.LayoutParams(-1, -2, Gravity.TOP))
        timerView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(16, 12, 16, 12)
            setBackgroundColor(0x99000000.toInt())
        }
        root.addView(timerView, FrameLayout.LayoutParams(-1, -2, Gravity.TOP).apply {
            topMargin = 64
        })
        root.addView(View(this).apply {
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(dp(2), Color.WHITE)
                cornerRadius = dp(12).toFloat()
            }
        }, FrameLayout.LayoutParams(dp(280), dp(150), Gravity.CENTER))
        torchButton = Button(this).apply {
            text = getString(com.workoutnotes.workout_notes.R.string.barcode_scanner_flashlight)
            isAllCaps = false
            setOnClickListener {
                val control = camera?.cameraControl ?: return@setOnClickListener
                val enabled = camera?.cameraInfo?.torchState?.value ==
                    androidx.camera.core.TorchState.ON
                control.enableTorch(!enabled)
                text = if (enabled) {
                    getString(com.workoutnotes.workout_notes.R.string.barcode_scanner_flashlight)
                } else {
                    getString(com.workoutnotes.workout_notes.R.string.barcode_scanner_flashlight_off)
                }
            }
        }
        root.addView(torchButton, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.END).apply {
            topMargin = 92
            rightMargin = 20
        })
        root.addView(Button(this).apply {
            text = getString(com.workoutnotes.workout_notes.R.string.barcode_scanner_cancel)
            isAllCaps = false
            setOnClickListener { finish() }
        }, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
            bottomMargin = 40
        })
        setContentView(root)
    }

    private fun startCamera() {
        try {
            val providerFuture = ProcessCameraProvider.getInstance(this)
            providerFuture.addListener({
                try {
                    val provider = providerFuture.get()
                    val preview = Preview.Builder().build().also {
                        it.surfaceProvider = previewView.surfaceProvider
                    }
                    val analysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                        .also { useCase ->
                            useCase.setAnalyzer(cameraExecutor) { proxy ->
                                val image = proxy.image
                                if (image == null || completed) {
                                    proxy.close()
                                    return@setAnalyzer
                                }
                                scanner.process(
                                    InputImage.fromMediaImage(
                                        image,
                                        proxy.imageInfo.rotationDegrees,
                                    ),
                                ).addOnSuccessListener { barcodes ->
                                    val barcode = barcodes.firstOrNull { isSupported(it.format) }
                                    val value = barcode?.rawValue
                                    if (value.isNullOrBlank() || barcode == null) return@addOnSuccessListener
                                    val detectedFormat =
                                        formatName(barcode.format) ?: return@addOnSuccessListener
                                    val key = "${barcode.format}:$value"
                                    if (key == lastValue) stableReads++ else {
                                        lastValue = key
                                        stableReads = 1
                                    }
                                    if (stableReads >= 2) complete(value, detectedFormat)
                                }.addOnCompleteListener { proxy.close() }
                            }
                        }
                    provider.unbindAll()
                    camera = provider.bindToLifecycle(
                        this,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis,
                    )
                } catch (_: Throwable) {
                    setResult(RESULT_CANCELED)
                    finish()
                }
            }, ContextCompat.getMainExecutor(this))
        } catch (_: Throwable) {
            // Some physical devices fail before CameraX returns its future.
            // Keep that device-specific error from terminating the app process.
            setResult(RESULT_CANCELED)
            finish()
        }
    }

    private fun complete(rawValue: String, format: String) {
        if (completed) return
        completed = true
        val enrollment = this@BarcodeScannerActivity.intent
            .getBooleanExtra(EXTRA_ENROLLMENT, false)
        val intent = Intent().apply {
            putExtra(EXTRA_RAW_VALUE, rawValue)
            putExtra(EXTRA_FORMAT, format)
            if (enrollment) {
                val salt = BarcodeMissionCrypto.newSalt()
                putExtra("hash", BarcodeMissionCrypto.hash(format, rawValue, salt))
                putExtra("salt", salt)
            }
        }
        timer?.cancel()
        setResult(RESULT_SUCCESS, intent)
        finish()
    }

    private fun startTimeoutTimer() {
        timer?.cancel()
        // General-purpose scans (nutrition) pass an explicit timeout;
        // the sleep mission falls back to the time left until the alarm.
        val explicitMillis = intent.getLongExtra(EXTRA_TIMEOUT_MILLIS, -1L)
        val remaining = if (explicitMillis > 0) {
            explicitMillis
        } else {
            SleepAlarmScheduler.barcodeRemainingMillis(this)
        }
        if (remaining <= 0L) {
            timeoutScanner()
            return
        }
        timer = object : CountDownTimer(remaining, 250L) {
            override fun onTick(millisUntilFinished: Long) {
                val seconds = ((millisUntilFinished + 999L) / 1000L).toInt()
                timerView.text = getString(
                    com.workoutnotes.workout_notes.R.string.barcode_scanner_time_left,
                    seconds,
                )
            }
            override fun onFinish() {
                timeoutScanner()
            }
        }.start()
    }

    private fun timeoutScanner() {
        if (completed) return
        completed = true
        timer?.cancel()
        setResult(RESULT_CANCELLED, Intent().putExtra(EXTRA_TIMEOUT, true))
        finish()
    }

    private fun isSupported(format: Int): Boolean = formatName(format) != null

    private fun formatName(format: Int): String? = when (format) {
        Barcode.FORMAT_EAN_8 -> "EAN-8"
        Barcode.FORMAT_EAN_13 -> "EAN-13"
        Barcode.FORMAT_UPC_A -> "UPC-A"
        Barcode.FORMAT_UPC_E -> "UPC-E"
        Barcode.FORMAT_CODE_128 -> "CODE-128"
        Barcode.FORMAT_CODE_39 -> "CODE-39"
        Barcode.FORMAT_CODE_93 -> "CODE-93"
        Barcode.FORMAT_CODABAR -> "CODABAR"
        Barcode.FORMAT_ITF -> "ITF"
        Barcode.FORMAT_QR_CODE -> "QR_CODE"
        else -> null
    }

    override fun onDestroy() {
        timer?.cancel()
        cameraExecutor.shutdown()
        scanner.close()
        super.onDestroy()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
