package com.acdmt

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.acdmt.data.DataCollector
import com.acdmt.model.MatchDecision
import com.acdmt.model.TrialPhase
import com.acdmt.render.StimulusRenderer
import com.acdmt.task.TrialRunner
import kotlin.math.roundToInt

class MainActivity : Activity(), TrialRunner.Callbacks {

    private lateinit var root: FrameLayout
    private lateinit var renderer: StimulusRenderer
    private lateinit var responseBar: LinearLayout
    private lateinit var dataCollector: DataCollector
    private lateinit var trialRunner: TrialRunner

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        applySystemBarColors()

        dataCollector = DataCollector()
        renderer = StimulusRenderer(this)
        trialRunner = TrialRunner(renderer, dataCollector, this)

        root = createContentView()
        setContentView(root)
        updateRendererScreenMetrics()
        showInstructions()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        root.post {
            updateRendererScreenMetrics()
            renderer.invalidate()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) updateRendererScreenMetrics()
    }

    override fun onDestroy() {
        trialRunner.dispose()
        super.onDestroy()
    }

    @Suppress("UNUSED_PARAMETER")
    override fun onPhaseChanged(phase: TrialPhase, trialNumber: Int, setSize: Int) {
        Unit
    }

    override fun onResponseWindowChanged(isOpen: Boolean) {
        responseBar.visibility = if (isOpen) View.VISIBLE else View.INVISIBLE
        responseBar.isEnabled = isOpen
    }

    override fun onExperimentFinished(json: String) {
        dataCollector.persistLatestSession(this)
        showExportView(json)
    }

    private fun createContentView(): FrameLayout {
        val frame = FrameLayout(this).apply {
            setBackgroundColor(StimulusRenderer.BACKGROUND_COLOR)
        }

        frame.addView(
            renderer,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        responseBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(10), dp(16), dp(16))
            setBackgroundColor(Color.argb(210, 33, 33, 36))
            visibility = View.INVISIBLE
        }

        val matchButton = createDecisionButton(
            label = "Match",
            backgroundColor = Color.rgb(52, 143, 80),
            decision = MatchDecision.MATCH
        )
        val mismatchButton = createDecisionButton(
            label = "Mismatch",
            backgroundColor = Color.rgb(181, 61, 55),
            decision = MatchDecision.MISMATCH
        )

        responseBar.addView(matchButton)
        responseBar.addView(mismatchButton)
        frame.addView(
            responseBar,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dp(86),
                Gravity.BOTTOM
            )
        )

        return frame
    }

    private fun createDecisionButton(
        label: String,
        backgroundColor: Int,
        decision: MatchDecision
    ): Button {
        return Button(this).apply {
            text = label
            textSize = 18f
            setTextColor(Color.WHITE)
            setBackgroundColor(backgroundColor)
            isAllCaps = false
            setOnClickListener { trialRunner.submitResponse(decision) }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f).apply {
                marginStart = dp(8)
                marginEnd = dp(8)
            }
        }
    }

    private fun applySystemBarColors() {
        val color = StimulusRenderer.BACKGROUND_COLOR
        @Suppress("DEPRECATION")
        window.statusBarColor = color
        @Suppress("DEPRECATION")
        window.navigationBarColor = color
    }

    private fun updateRendererScreenMetrics() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            renderer.setExternalScreenMetrics(bounds.width(), bounds.height())
        } else {
            @Suppress("DEPRECATION")
            val metrics = DisplayMetrics().also { windowManager.defaultDisplay.getMetrics(it) }
            renderer.setExternalScreenMetrics(metrics.widthPixels, metrics.heightPixels)
        }
    }

    private fun showExportView(json: String) {
        responseBar.visibility = View.GONE

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(StimulusRenderer.BACKGROUND_COLOR)
            setPadding(dp(20), dp(48), dp(20), dp(20))
        }

        val title = TextView(this).apply {
            text = "Experiment complete"
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity = Gravity.CENTER
        }

        val jsonText = TextView(this).apply {
            text = json
            setTextColor(Color.WHITE)
            textSize = 12f
            setTextIsSelectable(true)
            setPadding(0, dp(16), 0, dp(16))
        }

        val scrollView = ScrollView(this).apply {
            addView(jsonText)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        }

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        actionRow.addView(
            Button(this).apply {
                text = "Copy JSON"
                isAllCaps = false
                setOnClickListener { copyJson(json) }
                layoutParams = LinearLayout.LayoutParams(0, dp(54), 1f).apply {
                    marginEnd = dp(8)
                }
            }
        )
        actionRow.addView(
            Button(this).apply {
                text = "Share"
                isAllCaps = false
                setOnClickListener { shareJson(json) }
                layoutParams = LinearLayout.LayoutParams(0, dp(54), 1f).apply {
                    marginStart = dp(8)
                }
            }
        )

        panel.addView(title)
        panel.addView(scrollView)
        panel.addView(actionRow)

        root.addView(
            panel,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
    }

    private fun copyJson(json: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("ACDMT session JSON", json))
        Toast.makeText(this, "JSON copied", Toast.LENGTH_SHORT).show()
    }

    private fun shareJson(json: String) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_TEXT, json)
        }
        startActivity(Intent.createChooser(intent, "Export task data"))
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).roundToInt()
    }

    private fun showInstructions() {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(StimulusRenderer.BACKGROUND_COLOR)
            setPadding(dp(32), dp(48), dp(32), dp(32))
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
        }

        val text = TextView(this).apply {
            text = "You will see a fixation cross and then a cue to left or right.\n\n" +
                   "Focus only on the cued side.\n\n" +
                   "One of the color would change in cued side, position wont change.\n\n" +
                   "Press match if the initial array is ditto same as other and press mismatch if there is a mismatch.\n\n" +
                   "Tap anywhere to continue."
            setTextColor(Color.WHITE)
            textSize = 20f
            gravity = Gravity.CENTER
        }

        panel.addView(text)

        panel.setOnClickListener {
            root.removeView(panel)
            renderer.post { trialRunner.start() }
        }

        root.addView(
            panel,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
    }
}
