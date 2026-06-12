package com.acdmt.model

enum class Hemifield {
    LEFT,
    RIGHT;

    fun cueSymbol(): String = if (this == LEFT) "<" else ">"
}

enum class TrialPhase {
    IDLE,
    ITI,
    FIXATION,
    CUE,
    ENCODING,
    MAINTENANCE,
    RETRIEVAL,
    FINISHED
}

enum class MatchDecision(val exportLabel: String) {
    MATCH("match"),
    MISMATCH("mismatch"),
    NO_RESPONSE("no_response")
}

data class StimulusSlot(
    val xFraction: Float,
    val yFraction: Float
)

data class StimulusItem(
    val hemifield: Hemifield,
    val slot: StimulusSlot,
    val color: Int
)

data class TrialPlan(
    val trialNumber: Int,
    val setSize: Int,
    val cuedHemifield: Hemifield,
    val isMatchTrial: Boolean,
    val memoryItems: List<StimulusItem>,
    val testItems: List<StimulusItem>
)

data class TrialRecord(
    val trialNumber: Int,
    val setSize: Int,
    val cuedHemifield: Hemifield,
    val isMatchTrial: Boolean,
    val userResponse: MatchDecision,
    val accuracy: Int,
    val reactionTimeMs: Long?
)
