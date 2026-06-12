package com.acdmt.render

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import com.acdmt.model.Hemifield
import com.acdmt.model.StimulusItem
import com.acdmt.model.TrialPhase
import com.acdmt.model.TrialPlan
import kotlin.math.min

class StimulusRenderer @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private var phase: TrialPhase = TrialPhase.IDLE
    private var currentTrial: TrialPlan? = null
    private var cueHemifield: Hemifield? = null
    private var externalScreenWidth = 0
    private var externalScreenHeight = 0

    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
    }

    private val stimulusPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private val stimulusBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(190, 0, 0, 0)
        style = Paint.Style.STROKE
        strokeWidth = 2f
    }

    init {
        setBackgroundColor(BACKGROUND_COLOR)
        isFocusable = true
    }

    fun setExternalScreenMetrics(widthPixels: Int, heightPixels: Int) {
        externalScreenWidth = widthPixels
        externalScreenHeight = heightPixels
        invalidate()
    }

    fun showBlank(blankPhase: TrialPhase = TrialPhase.ITI) {
        phase = blankPhase
        currentTrial = null
        cueHemifield = null
        invalidate()
    }

    fun showFixation(fixationPhase: TrialPhase = TrialPhase.FIXATION) {
        phase = fixationPhase
        currentTrial = null
        cueHemifield = null
        invalidate()
    }

    fun showCue(hemifield: Hemifield) {
        phase = TrialPhase.CUE
        currentTrial = null
        cueHemifield = hemifield
        invalidate()
    }

    fun showEncoding(trial: TrialPlan) {
        phase = TrialPhase.ENCODING
        currentTrial = trial
        cueHemifield = trial.cuedHemifield
        invalidate()
    }

    fun showMaintenance() {
        phase = TrialPhase.MAINTENANCE
        invalidate()
    }

    fun showRetrieval(trial: TrialPlan) {
        phase = TrialPhase.RETRIEVAL
        currentTrial = trial
        cueHemifield = trial.cuedHemifield
        invalidate()
    }

    fun showFinished() {
        phase = TrialPhase.FINISHED
        currentTrial = null
        cueHemifield = null
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(BACKGROUND_COLOR)

        val geometry = calculateGeometry()
        when (phase) {
            TrialPhase.FIXATION,
            TrialPhase.MAINTENANCE -> drawFixation(canvas, geometry)
            TrialPhase.CUE -> drawCue(canvas, geometry)
            TrialPhase.ENCODING -> {
                drawFixation(canvas, geometry)
                currentTrial?.let { drawStimuli(canvas, it.memoryItems, geometry) }
            }
            TrialPhase.RETRIEVAL -> {
                drawFixation(canvas, geometry)
                currentTrial?.let { drawStimuli(canvas, it.testItems, geometry) }
            }
            TrialPhase.IDLE,
            TrialPhase.ITI,
            TrialPhase.FINISHED -> Unit
        }
    }

    private fun calculateGeometry(): Geometry {
        val screenWidth = when {
            width > 0 -> width
            externalScreenWidth > 0 -> externalScreenWidth
            else -> resources.displayMetrics.widthPixels
        }.toFloat()

        val screenHeight = when {
            height > 0 -> height
            externalScreenHeight > 0 -> externalScreenHeight
            else -> resources.displayMetrics.heightPixels
        }.toFloat()

        val fixationX = screenWidth * 0.5f
        val fixationY = screenHeight * 0.5f
        val sideMargin = screenWidth * 0.045f
        val centralGap = screenWidth * 0.105f
        val verticalTop = screenHeight * 0.20f
        val verticalBottom = screenHeight * 0.74f
        val squareSide = min(screenWidth * 0.068f, screenHeight * 0.058f)

        val leftHemifield = RectF(
            sideMargin,
            verticalTop,
            fixationX - centralGap,
            verticalBottom
        )
        val rightHemifield = RectF(
            fixationX + centralGap,
            verticalTop,
            screenWidth - sideMargin,
            verticalBottom
        )
        val leftStimulusBox = centeredBoxIn(leftHemifield, widthScale = 0.96f, heightScale = 0.72f)
        val rightStimulusBox = centeredBoxIn(rightHemifield, widthScale = 0.96f, heightScale = 0.72f)

        return Geometry(
            screenWidth = screenWidth,
            screenHeight = screenHeight,
            fixationX = fixationX,
            fixationY = fixationY,
            squareSide = squareSide,
            leftStimulusBox = leftStimulusBox,
            rightStimulusBox = rightStimulusBox
        )
    }

    private fun drawFixation(canvas: Canvas, geometry: Geometry) {
        textPaint.color = Color.WHITE
        textPaint.textSize = min(geometry.screenWidth, geometry.screenHeight) * 0.11f
        drawCenteredText(canvas, "+", geometry.fixationX, geometry.fixationY, textPaint)
    }

    private fun drawCue(canvas: Canvas, geometry: Geometry) {
        val symbol = cueHemifield?.cueSymbol().orEmpty()
        textPaint.color = Color.WHITE
        textPaint.textSize = min(geometry.screenWidth, geometry.screenHeight) * 0.16f
        drawCenteredText(canvas, symbol, geometry.fixationX, geometry.fixationY, textPaint)
    }

    private fun drawStimuli(canvas: Canvas, items: List<StimulusItem>, geometry: Geometry) {
        items.forEach { item ->
            val rect = rectFor(item, geometry)
            stimulusPaint.color = item.color
            canvas.drawRect(rect, stimulusPaint)
            stimulusBorderPaint.strokeWidth = geometry.squareSide * 0.045f
            canvas.drawRect(rect, stimulusBorderPaint)
        }
    }

    private fun rectFor(item: StimulusItem, geometry: Geometry): RectF {
        val box = if (item.hemifield == Hemifield.LEFT) {
            geometry.leftStimulusBox
        } else {
            geometry.rightStimulusBox
        }
        val centerX = box.centerX()
        val centerY = box.centerY()
        val horizontalRadius = ((box.width() - geometry.squareSide) * 0.5f).coerceAtLeast(0f)
        val verticalRadius = ((box.height() - geometry.squareSide) * 0.5f).coerceAtLeast(0f)
        val halfSide = geometry.squareSide * 0.5f

        val squareCenterX = centerX + item.slot.xFraction * horizontalRadius
        val squareCenterY = centerY + item.slot.yFraction * verticalRadius

        val left = (squareCenterX - halfSide).coerceIn(box.left, box.right - geometry.squareSide)
        val top = (squareCenterY - halfSide).coerceIn(box.top, box.bottom - geometry.squareSide)
        return RectF(left, top, left + geometry.squareSide, top + geometry.squareSide)
    }

    private fun centeredBoxIn(bounds: RectF, widthScale: Float, heightScale: Float): RectF {
        val boxWidth = bounds.width() * widthScale
        val boxHeight = bounds.height() * heightScale
        val left = bounds.centerX() - boxWidth * 0.5f
        val top = bounds.centerY() - boxHeight * 0.5f
        return RectF(left, top, left + boxWidth, top + boxHeight)
    }

    private fun drawCenteredText(
        canvas: Canvas,
        text: String,
        centerX: Float,
        centerY: Float,
        paint: Paint
    ) {
        val metrics = paint.fontMetrics
        val baseline = centerY - (metrics.ascent + metrics.descent) * 0.5f
        canvas.drawText(text, centerX, baseline, paint)
    }

    private data class Geometry(
        val screenWidth: Float,
        val screenHeight: Float,
        val fixationX: Float,
        val fixationY: Float,
        val squareSide: Float,
        val leftStimulusBox: RectF,
        val rightStimulusBox: RectF
    )

    companion object {
        val BACKGROUND_COLOR: Int = Color.rgb(45, 45, 48)
    }
}
