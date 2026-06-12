package com.acdmt.data

import android.content.Context
import com.acdmt.model.TrialRecord
import org.json.JSONArray
import org.json.JSONObject

class DataCollector {
    private val records = mutableListOf<TrialRecord>()

    fun log(record: TrialRecord) {
        records += record
    }

    fun clear() {
        records.clear()
    }

    fun allRecords(): List<TrialRecord> = records.toList()

    fun exportJsonString(): String {
        val rows = JSONArray()
        records.forEach { record ->
            rows.put(
                JSONObject()
                    .put("trial_number", record.trialNumber)
                    .put("set_size", record.setSize)
                    .put("cued_hemifield", record.cuedHemifield.name.lowercase())
                    .put("is_match_trial", record.isMatchTrial)
                    .put("user_response", record.userResponse.exportLabel)
                    .put("accuracy", record.accuracy)
                    .put("reaction_time_ms", record.reactionTimeMs ?: JSONObject.NULL)
            )
        }
        return rows.toString(2)
    }

    fun persistLatestSession(context: Context) {
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LATEST_SESSION_JSON, exportJsonString())
            .apply()
    }

    companion object {
        private const val PREFS_NAME = "acdmt_data"
        private const val KEY_LATEST_SESSION_JSON = "latest_session_json"
    }
}
