package app.revelio.ui.scan

import android.annotation.SuppressLint
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage

/**
 * `ImageAnalysis.Analyzer` wrapping ML Kit's Barcode Scanner. Only the formats
 * Revelio needs (EAN-8/13, UPC-A/E, Code-128 for supplements) are enabled —
 * this keeps the ML Kit model small and recognition fast.
 *
 * Callers receive the raw barcode value via [onBarcode]. We dedupe here so
 * the UI doesn't get spammed; the caller decides whether to navigate.
 */
class BarcodeAnalyzer(
    private val onBarcode: (String) -> Unit,
) : ImageAnalysis.Analyzer {

    private val scanner: BarcodeScanner by lazy {
        val options = BarcodeScannerOptions.Builder()
            .setBarcodeFormats(
                Barcode.FORMAT_EAN_13,
                Barcode.FORMAT_EAN_8,
                Barcode.FORMAT_UPC_A,
                Barcode.FORMAT_UPC_E,
                Barcode.FORMAT_CODE_128,
            )
            .build()
        BarcodeScanning.getClient(options)
    }

    @Volatile
    private var lastReported: String? = null

    @SuppressLint("UnsafeOptInUsageError")
    override fun analyze(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }
        val inputImage = InputImage.fromMediaImage(
            mediaImage,
            imageProxy.imageInfo.rotationDegrees,
        )
        scanner.process(inputImage)
            .addOnSuccessListener { barcodes ->
                barcodes.firstOrNull()?.rawValue?.takeIf { it.isNotBlank() }?.let { value ->
                    if (value != lastReported) {
                        lastReported = value
                        onBarcode(value)
                    }
                }
            }
            .addOnCompleteListener { imageProxy.close() }
    }
}
