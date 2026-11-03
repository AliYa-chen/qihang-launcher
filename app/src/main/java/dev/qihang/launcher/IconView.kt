package dev.qihang.launcher

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View

enum class Glyph { BRAND, HOME, APPS, CAR, DIAGNOSTICS, DOOR_LEFT, DOOR_RIGHT, WINDOW, TRUNK, LIGHTS, RESET, CLOSE, ORBIT, SHARE, CHECK }

/** Small original line glyphs, drawn consistently at a 24-unit scale. */
class IconView(context: Context, val glyph: Glyph, color: Int) : View(context) {
    var iconColor: Int = color
        set(value) { field = value; invalidate() }
    private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.6f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val scale = minOf(width, height) / 28f
        canvas.save()
        canvas.translate((width - 24 * scale) / 2, (height - 24 * scale) / 2)
        canvas.scale(scale, scale)
        p.color = iconColor
        fun line(x1: Float, y1: Float, x2: Float, y2: Float) = canvas.drawLine(x1, y1, x2, y2, p)
        fun path(vararg pts: Float) {
            val shape = Path().apply { moveTo(pts[0], pts[1]); var i = 2; while (i < pts.size) { lineTo(pts[i], pts[i + 1]); i += 2 } }
            canvas.drawPath(shape, p)
        }
        when (glyph) {
            Glyph.BRAND -> { path(3f, 18f, 12f, 3f, 21f, 18f, 13f, 14f, 12f, 21f, 10f, 14f, 3f, 18f); line(12f, 3f, 12f, 12f) }
            Glyph.HOME -> { path(3f, 10f, 12f, 3f, 21f, 10f); path(5f, 9f, 5f, 21f, 10f, 21f, 10f, 15f, 14f, 15f, 14f, 21f, 19f, 21f, 19f, 9f) }
            Glyph.APPS -> { for (x in listOf(4f, 14f)) for (y in listOf(4f, 14f)) canvas.drawRoundRect(x, y, x + 6, y + 6, 1.5f, 1.5f, p) }
            Glyph.CAR -> { path(3f, 12f, 6f, 5f, 18f, 5f, 21f, 12f, 21f, 19f, 3f, 19f, 3f, 12f); line(4f, 12f, 20f, 12f); line(6f, 15f, 8f, 15f); line(16f, 15f, 18f, 15f); line(5f, 19f, 5f, 21f); line(19f, 19f, 19f, 21f) }
            Glyph.DIAGNOSTICS -> { path(5f, 3f, 19f, 3f, 19f, 21f, 5f, 21f, 5f, 3f); path(8f, 13f, 10f, 13f, 12f, 9f, 14f, 16f, 16f, 12f); line(8f, 6f, 15f, 6f) }
            Glyph.DOOR_LEFT -> { path(5f, 20f, 5f, 10f, 10f, 4f, 19f, 4f, 19f, 20f, 5f, 20f); path(8f, 10f, 11f, 6f, 16f, 6f, 16f, 11f, 8f, 11f); line(14f, 15f, 17f, 15f) }
            Glyph.DOOR_RIGHT -> { path(19f, 20f, 19f, 10f, 14f, 4f, 5f, 4f, 5f, 20f, 19f, 20f); path(16f, 10f, 13f, 6f, 8f, 6f, 8f, 11f, 16f, 11f); line(7f, 15f, 10f, 15f) }
            Glyph.WINDOW -> { path(3f, 18f, 6f, 6f, 18f, 6f, 21f, 18f, 3f, 18f); line(12f, 7f, 12f, 17f); line(4f, 12f, 20f, 12f) }
            Glyph.TRUNK -> { path(4f, 14f, 7f, 9f, 17f, 9f, 20f, 14f, 20f, 20f, 4f, 20f, 4f, 14f); path(7f, 9f, 6f, 5f, 18f, 5f, 17f, 9f); line(4f, 15f, 20f, 15f); line(10f, 17f, 14f, 17f) }
            Glyph.LIGHTS -> { val shape = Path().apply { moveTo(13f, 5f); cubicTo(5f, 4f, 3f, 8f, 3f, 12f); cubicTo(3f, 16f, 5f, 20f, 13f, 19f); close() }; canvas.drawPath(shape, p); line(16f, 6f, 21f, 4f); line(16f, 10f, 22f, 9f); line(16f, 14f, 22f, 14f); line(16f, 18f, 21f, 20f) }
            Glyph.RESET -> { canvas.drawArc(4f, 4f, 20f, 20f, -50f, 290f, false, p); path(3f, 4f, 3f, 10f, 9f, 10f) }
            Glyph.CLOSE -> { line(6f, 6f, 18f, 18f); line(18f, 6f, 6f, 18f) }
            Glyph.ORBIT -> { canvas.drawOval(2f, 7f, 22f, 17f, p); canvas.drawOval(8f, 2f, 16f, 22f, p) }
            Glyph.SHARE -> { line(12f, 15f, 12f, 3f); path(8f, 7f, 12f, 3f, 16f, 7f); path(5f, 12f, 5f, 21f, 19f, 21f, 19f, 12f) }
            Glyph.CHECK -> path(5f, 12f, 10f, 17f, 20f, 6f)
        }
        canvas.restore()
    }
}
