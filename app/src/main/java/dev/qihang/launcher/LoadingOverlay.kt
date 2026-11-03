package dev.qihang.launcher

import android.annotation.TargetApi
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import java.util.concurrent.Executors
import kotlin.math.exp
import kotlin.math.roundToInt

/** A blurred scene poster covers engine initialization until its first frame. */
class LoadingOverlay(context: Context) : FrameLayout(context) {
    private val backdrop = ImageView(context).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "QihangLoadingPoster").apply { isDaemon = true }
    }
    @Volatile private var disposed = false
    private var finishing = false

    init {
        setBackgroundColor(BACKGROUND)
        isClickable = true
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = "正在准备车辆"
        addView(backdrop, LayoutParams(-1, -1))
        addView(View(context).apply {
            setBackgroundColor(Color.argb(100, 0, 0, 0))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LayoutParams(-1, -1))

        val indicator = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        indicator.addView(ProgressBar(context, null, android.R.attr.progressBarStyleSmall).apply {
            isIndeterminate = true
            indeterminateTintList = ColorStateList.valueOf(Color.rgb(222, 232, 235))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(dp(30), dp(30)))
        indicator.addView(TextView(context).apply {
            text = "正在准备车辆"
            textSize = 13f
            setTextColor(Color.rgb(205, 214, 219))
            includeFontPadding = false
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(15) })
        addView(indicator, LayoutParams(-2, -2, Gravity.CENTER))
        loadPoster()
    }

    /** Called only after Godot has rendered the actual scene's first frame. */
    fun revealScene(onFinished: () -> Unit) {
        if (finishing) return
        finishing = true
        animate().cancel()
        animate().alpha(0f).setDuration(350).withEndAction { onFinished() }.start()
    }

    override fun onDetachedFromWindow() {
        disposed = true
        worker.shutdownNow()
        animate().cancel()
        super.onDetachedFromWindow()
    }

    private fun loadPoster() {
        worker.execute {
            try {
                val poster = decodePoster() ?: return@execute
                // API 30 has no RenderEffect. Its fallback is a real two-pass
                // Gaussian convolution, executed on this downsampled bitmap.
                val blurred = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) poster else gaussianBlur(poster, radius = 18, sigma = 8f)
                if (disposed || Thread.currentThread().isInterrupted) return@execute
                post {
                    if (!disposed && !finishing) {
                        backdrop.setImageBitmap(blurred)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) applyGpuBlur()
                    }
                }
            } catch (_: Exception) {
                // The neutral backdrop and spinner remain usable if the bundled
                // poster cannot be decoded; initialization itself is unaffected.
            }
        }
    }

    private fun decodePoster(): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.assets.open("loading-vehicle.png").use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 480) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = context.assets.open("loading-vehicle.png").use { BitmapFactory.decodeStream(it, null, options) } ?: return null
        // Flatten alpha before convolution so translucent source pixels cannot
        // introduce dark/transparent fringes around the vehicle.
        return Bitmap.createBitmap(decoded.width, decoded.height, Bitmap.Config.ARGB_8888).also { flat ->
            val canvas = Canvas(flat)
            canvas.drawColor(BACKGROUND)
            canvas.drawBitmap(decoded, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG))
        }
    }

    @TargetApi(Build.VERSION_CODES.S)
    private fun applyGpuBlur() {
        val blurPixels = 30f * resources.displayMetrics.density
        backdrop.setRenderEffect(RenderEffect.createBlurEffect(blurPixels, blurPixels, Shader.TileMode.CLAMP))
    }

    private fun gaussianBlur(bitmap: Bitmap, radius: Int, sigma: Float): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val source = IntArray(width * height)
        val horizontal = IntArray(source.size)
        val result = IntArray(source.size)
        bitmap.getPixels(source, 0, width, 0, 0, width, height)
        val kernel = FloatArray(radius * 2 + 1)
        var sum = 0f
        for (offset in -radius..radius) {
            val weight = exp(-(offset * offset).toFloat() / (2f * sigma * sigma))
            kernel[offset + radius] = weight
            sum += weight
        }
        for (i in kernel.indices) kernel[i] /= sum

        fun pack(red: Float, green: Float, blue: Float): Int =
            Color.rgb(red.roundToInt().coerceIn(0, 255), green.roundToInt().coerceIn(0, 255), blue.roundToInt().coerceIn(0, 255))

        for (y in 0 until height) {
            if (Thread.currentThread().isInterrupted) throw InterruptedException()
            val row = y * width
            for (x in 0 until width) {
                var red = 0f; var green = 0f; var blue = 0f
                for (offset in -radius..radius) {
                    val pixel = source[row + (x + offset).coerceIn(0, width - 1)]
                    val weight = kernel[offset + radius]
                    red += Color.red(pixel) * weight
                    green += Color.green(pixel) * weight
                    blue += Color.blue(pixel) * weight
                }
                horizontal[row + x] = pack(red, green, blue)
            }
        }
        for (y in 0 until height) {
            if (Thread.currentThread().isInterrupted) throw InterruptedException()
            for (x in 0 until width) {
                var red = 0f; var green = 0f; var blue = 0f
                for (offset in -radius..radius) {
                    val pixel = horizontal[(y + offset).coerceIn(0, height - 1) * width + x]
                    val weight = kernel[offset + radius]
                    red += Color.red(pixel) * weight
                    green += Color.green(pixel) * weight
                    blue += Color.blue(pixel) * weight
                }
                result[y * width + x] = pack(red, green, blue)
            }
        }
        return Bitmap.createBitmap(result, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + .5f).toInt()

    companion object {
        private val BACKGROUND = Color.rgb(22, 23, 24)
    }
}
