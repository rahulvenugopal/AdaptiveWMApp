package com.acdmt.task

import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.acdmt.data.DataCollector
import com.acdmt.model.Hemifield
import com.acdmt.model.MatchDecision
import com.acdmt.model.StimulusItem
import com.acdmt.model.StimulusSlot
import com.acdmt.model.TrialPhase
import com.acdmt.model.TrialPlan
import com.acdmt.model.TrialRecord
import com.acdmt.render.StimulusRenderer
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.random.Random

class TrialRunner(
    private val renderer: StimulusRenderer,
    private val dataCollector: DataCollector,
    private val callbacks: Callbacks,
    private val random: Random = Random(System.currentTimeMillis())
) {
    interface Callbacks {
        fun onPhaseChanged(phase: TrialPhase, trialNumber: Int, setSize: Int)
        fun onResponseWindowChanged(isOpen: Boolean)
        fun onExperimentFinished(json: String)
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val handler = Handler(Looper.getMainLooper())
    private var runJob: Job? = null
    private var currentPhase: TrialPhase = TrialPhase.IDLE
    private var currentSetSize = START_SET_SIZE
    private var consecutiveCorrect = 0
    private var responseDeferred: CompletableDeferred<ResponseEvent>? = null
    private var retrievalOnsetMs = 0L

    fun start() {
        if (runJob?.isActive == true) return

        dataCollector.clear()
        currentSetSize = START_SET_SIZE
        consecutiveCorrect = 0
        runJob = scope.launch {
            runExperiment()
        }
    }

    fun stop() {
        runJob?.cancel()
        responseDeferred?.cancel()
        handler.removeCallbacksAndMessages(null)
        callbacks.onResponseWindowChanged(false)
    }

    fun dispose() {
        stop()
        scope.cancel()
    }

    fun submitResponse(decision: MatchDecision) {
        if (decision == MatchDecision.NO_RESPONSE) return
        val pending = responseDeferred ?: return
        if (currentPhase != TrialPhase.RETRIEVAL || !pending.isActive) return

        val reactionTime = SystemClock.elapsedRealtime() - retrievalOnsetMs
        pending.complete(ResponseEvent(decision, reactionTime))
    }

    private suspend fun runExperiment() {
        for (trialNumber in 1..TOTAL_TRIALS) {
            val trial = createTrialPlan(trialNumber, currentSetSize)
            runTrial(trial)
        }

        transitionTo(TrialPhase.FINISHED, null)
        callbacks.onExperimentFinished(dataCollector.exportJsonString())
    }

    private suspend fun runTrial(trial: TrialPlan) {
        transitionTo(TrialPhase.ITI, trial)
        scheduledDelay(random.nextLong(ITI_MIN_MS, ITI_MAX_MS + 1))

        transitionTo(TrialPhase.FIXATION, trial)
        scheduledDelay(FIXATION_MS)

        transitionTo(TrialPhase.CUE, trial)
        scheduledDelay(CUE_MS)

        transitionTo(TrialPhase.ENCODING, trial)
        scheduledDelay(ENCODING_MS)

        transitionTo(TrialPhase.MAINTENANCE, trial)
        scheduledDelay(MAINTENANCE_MS)

        val response = runRetrieval(trial)
        val userDecision = response?.decision ?: MatchDecision.NO_RESPONSE
        val accuracy = if (isCorrect(userDecision, trial)) 1 else 0

        dataCollector.log(
            TrialRecord(
                trialNumber = trial.trialNumber,
                setSize = trial.setSize,
                cuedHemifield = trial.cuedHemifield,
                isMatchTrial = trial.isMatchTrial,
                userResponse = userDecision,
                accuracy = accuracy,
                reactionTimeMs = response?.reactionTimeMs
            )
        )

        updateStaircase(accuracy == 1)
    }

    private suspend fun runRetrieval(trial: TrialPlan): ResponseEvent? {
        responseDeferred = CompletableDeferred()
        retrievalOnsetMs = SystemClock.elapsedRealtime()
        transitionTo(TrialPhase.RETRIEVAL, trial)
        callbacks.onResponseWindowChanged(true)

        val response = withTimeoutOrNull(RETRIEVAL_MS) {
            responseDeferred?.await()
        }

        callbacks.onResponseWindowChanged(false)
        responseDeferred = null
        return response
    }

    private fun transitionTo(phase: TrialPhase, trial: TrialPlan?) {
        currentPhase = phase
        when (phase) {
            TrialPhase.ITI -> renderer.showBlank(phase)
            TrialPhase.FIXATION -> renderer.showFixation(phase)
            TrialPhase.CUE -> renderer.showCue(requireNotNull(trial).cuedHemifield)
            TrialPhase.ENCODING -> renderer.showEncoding(requireNotNull(trial))
            TrialPhase.MAINTENANCE -> renderer.showMaintenance()
            TrialPhase.RETRIEVAL -> renderer.showRetrieval(requireNotNull(trial))
            TrialPhase.FINISHED -> renderer.showFinished()
            TrialPhase.IDLE -> renderer.showBlank(phase)
        }
        callbacks.onPhaseChanged(phase, trial?.trialNumber ?: TOTAL_TRIALS, trial?.setSize ?: currentSetSize)
    }

    private suspend fun scheduledDelay(durationMs: Long) {
        suspendCancellableCoroutine { continuation ->
            val runnable = Runnable {
                if (continuation.isActive) continuation.resume(Unit)
            }
            handler.postDelayed(runnable, durationMs)
            continuation.invokeOnCancellation {
                handler.removeCallbacks(runnable)
            }
        }
    }

    private fun createTrialPlan(trialNumber: Int, setSize: Int): TrialPlan {
        val cuedHemifield = if (random.nextBoolean()) Hemifield.LEFT else Hemifield.RIGHT
        val isMatchTrial = random.nextBoolean()
        val leftItems = createHemifieldItems(Hemifield.LEFT, setSize)
        val rightItems = createHemifieldItems(Hemifield.RIGHT, setSize)
        val cuedItems = if (cuedHemifield == Hemifield.LEFT) leftItems else rightItems
        val uncuedItems = if (cuedHemifield == Hemifield.LEFT) rightItems else leftItems
        val cuedTestItems = if (isMatchTrial) {
            cuedItems.map { it.copy() }
        } else {
            createMismatchItems(cuedItems)
        }
        val testItems = if (cuedHemifield == Hemifield.LEFT) {
            cuedTestItems + uncuedItems.map { it.copy() }
        } else {
            uncuedItems.map { it.copy() } + cuedTestItems
        }

        return TrialPlan(
            trialNumber = trialNumber,
            setSize = setSize,
            cuedHemifield = cuedHemifield,
            isMatchTrial = isMatchTrial,
            memoryItems = leftItems + rightItems,
            testItems = testItems
        )
    }

    private fun createHemifieldItems(hemifield: Hemifield, setSize: Int): List<StimulusItem> {
        val selectedSlots = SLOT_TEMPLATE.shuffled(random).take(setSize)
        val selectedColors = COLOR_PALETTE.shuffled(random).take(setSize)
        return selectedSlots.zip(selectedColors).map { (slot, color) ->
            StimulusItem(
                hemifield = hemifield,
                slot = slot,
                color = color
            )
        }
    }

    private fun createMismatchItems(cuedItems: List<StimulusItem>): List<StimulusItem> {
        val changedIndex = random.nextInt(cuedItems.size)
        val usedColors = cuedItems.map { it.color }.toSet()
        return cuedItems.mapIndexed { index, item ->
            if (index != changedIndex) {
                item.copy()
            } else {
                // Exclude ALL colors already in this hemifield, not just the replaced item's color
                val replacement = COLOR_PALETTE
                    .filter { it !in usedColors }
                    .random(random)
                item.copy(color = replacement)
            }
        }
    }

    private fun isCorrect(decision: MatchDecision, trial: TrialPlan): Boolean {
        return when (decision) {
            MatchDecision.MATCH -> trial.isMatchTrial
            MatchDecision.MISMATCH -> !trial.isMatchTrial
            MatchDecision.NO_RESPONSE -> false
        }
    }

    private fun updateStaircase(wasCorrect: Boolean) {
        if (wasCorrect) {
            consecutiveCorrect += 1
            if (consecutiveCorrect >= 2) {
                currentSetSize = (currentSetSize + 1).coerceIn(MIN_SET_SIZE, MAX_SET_SIZE)
                consecutiveCorrect = 0
            }
        } else {
            consecutiveCorrect = 0
            currentSetSize = (currentSetSize - 1).coerceIn(MIN_SET_SIZE, MAX_SET_SIZE)
        }
    }

    private data class ResponseEvent(
        val decision: MatchDecision,
        val reactionTimeMs: Long
    )

    companion object {
        const val TOTAL_TRIALS = 100
        const val START_SET_SIZE = 2
        const val MIN_SET_SIZE = 3
        const val MAX_SET_SIZE = 8

        private const val ITI_MIN_MS  = 300L
        private const val ITI_MAX_MS  = 800L
        private const val FIXATION_MS = 500L
        private const val CUE_MS      = 300L
        private const val ENCODING_MS = 300L
        private const val MAINTENANCE_MS = 1_000L
        private const val RETRIEVAL_MS   = 2_000L

        private val SLOT_TEMPLATE = listOf(
            StimulusSlot(-0.82f, -0.58f),
            StimulusSlot(0f, -0.72f),
            StimulusSlot(0.82f, -0.58f),
            StimulusSlot(-0.82f, 0f),
            StimulusSlot(0.82f, 0f),
            StimulusSlot(-0.82f, 0.58f),
            StimulusSlot(0f, 0.72f),
            StimulusSlot(0.82f, 0.58f)
        )

        private val COLOR_PALETTE = listOf(
            Color.rgb(228, 30,  40),   // Red      H≈ 0°
            Color.rgb(242, 128, 20),   // Orange   H≈27°
            Color.rgb(242, 215, 20),   // Yellow   H≈53°
            Color.rgb(100, 222, 20),   // Lime     H≈93°
            Color.rgb(20,  188, 90),   // Green    H≈143°
            Color.rgb(20,  215, 222),  // Cyan     H≈182°
            Color.rgb(20,  100, 222),  // Blue     H≈216°
            Color.rgb(138, 20,  222),  // Purple   H≈276°
            Color.rgb(222, 20,  165),  // Magenta  H≈311°
            Color.WHITE                // White    achromatic
        )
    }
}
