package com.example.hello_flutter

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import java.io.ByteArrayInputStream
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.example.hello_flutter/game_detect"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            if (call.method == "game_detect") {
                val imageBytes = call.argument<ByteArray>("image")
                if (imageBytes != null) {
                    val response = handleImageProcessing(imageBytes)
                    result.success(response)
                } else {
                    result.error("UNAVAILABLE", "Image data not available.", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }


    fun floatArrayToByteArray(floatArray: Array<Array<Array<FloatArray>>>): ByteArray {
        val byteBuffer = ByteBuffer.allocate(4 * floatArray.size * floatArray[0].size * floatArray[0][0].size * floatArray[0][0][0].size)
        byteBuffer.order(ByteOrder.LITTLE_ENDIAN)
        
        for (i in floatArray.indices) {
            for (j in floatArray[i].indices) {
                for (k in floatArray[i][j].indices) {
                    for (l in floatArray[i][j][k].indices) {
                        byteBuffer.putFloat(floatArray[i][j][k][l])
                    }
                }
            }
        }
        
        return byteBuffer.array()
    }

    private fun handleImageProcessing(imageBytes: ByteArray): ByteArray{
        val result = Array(1) {
            Array(512) {
                Array(512) {
                    FloatArray(1)
                }
            }
        }

        val bitmap = BitmapFactory.decodeStream(ByteArrayInputStream(imageBytes))

        context.assets.openFd(MODEL_PATH).use { fileDescriptor ->
            FileInputStream(fileDescriptor.fileDescriptor).use { inputStream ->
                inputStream.channel.use { fileChannel ->
                    Interpreter(
                        fileChannel.map(
                            FileChannel.MapMode.READ_ONLY,
                            fileDescriptor.startOffset,
                            fileDescriptor.declaredLength
                        ),
                        Interpreter.Options().apply { numThreads = 5 }
                    ).use { interpreter ->
                        val scaledBitmap = Bitmap.createScaledBitmap(
                            bitmap,
                            INPUT_SIZE,
                            INPUT_SIZE,
                            false
                        )
                        val byteBuffer = convertBitmapToByteBuffer(scaledBitmap)
                        interpreter.run(byteBuffer, result)
                    }
                }
            }
        }
        return floatArrayToByteArray(result)
    }

    private fun convertBitmapToByteBuffer(bitmap: Bitmap): ByteBuffer {
        val byteBuffer = ByteBuffer.allocateDirect(4 * INPUT_SIZE * INPUT_SIZE * PIXEL_SIZE)
        byteBuffer.order(ByteOrder.nativeOrder())
        val intValues = IntArray(INPUT_SIZE * INPUT_SIZE)

        bitmap.getPixels(intValues, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        var pixel = 0
        for (i in 0 until INPUT_SIZE) {
            for (j in 0 until INPUT_SIZE) {
                val input = intValues[pixel++]

                byteBuffer.putFloat((((input.shr(16) and 0xFF) - IMAGE_MEAN) / IMAGE_STD))
                byteBuffer.putFloat((((input.shr(8) and 0xFF) - IMAGE_MEAN) / IMAGE_STD))
                byteBuffer.putFloat((((input and 0xFF) - IMAGE_MEAN) / IMAGE_STD))
            }
        }
        return byteBuffer
    }

    companion object {
        private const val MODEL_PATH = "model.tflite"
        private const val INPUT_SIZE = 512
        private const val OUTPUT_SIZE = 512 *512
        private const val PIXEL_SIZE = 3
        private const val IMAGE_MEAN = 0
        private const val IMAGE_STD = 255.0f
        private const val THRESHOLD = 0.4f
    }
}