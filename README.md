# ACDMT Android Core

Native Kotlin implementation of a 100-trial lateralized delayed match-to-sample task.

Core files:

- `TrialRunner`: coroutine plus `Handler` state machine for ITI, fixation, cue, encoding, maintenance, and retrieval.
- `StimulusRenderer`: custom `View` that computes fixation, hemifield bounds, square sizes, and square locations from current screen proportions.
- `DataCollector`: in-memory trial log with JSON export and latest-session persistence.
- `MainActivity`: wires the renderer, response buttons, progress display, and export screen.

The first trial starts at set size 2 as requested. After staircase adjustment, set size is bounded to 3 through 8.
