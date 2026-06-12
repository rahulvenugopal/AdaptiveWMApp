# AdaptiveWMApp: Lateralized Delayed Match-to-Sample Task

A native Kotlin Android application implementing a 100-trial lateralized delayed match-to-sample working memory task. This tool is built for high-precision cognitive science research, featuring staircase adjustments for set sizes and reliable in-memory trial logging.

<div align="center">
  
  https://github.com/user-attachments/assets/d1fafda4-7a04-4f86-8656-af68b3199605

  </div>

## 🧠 Task Paradigm
The application runs a 100-trial session encompassing the following states:
* **ITI (Inter-Trial Interval)**
* **Fixation**
* **Cue**
* **Encoding**
* **Maintenance**
* **Retrieval**

The first trial begins at a set size of 2. Following staircase adjustment, the set size dynamically scales and is bounded between 3 and 8. Hemifield bounds, square sizes, and locations are mathematically computed from current screen proportions by the `StimulusRenderer` to ensure visual consistency across different devices.

## 💾 Data Export & Integration
To support advanced analytical tools and cognitive transition tracking, `DataCollector` maintains an in-memory trial log. 
* Exports seamlessly to **JSON** format.
* Includes latest-session persistence.
* Structured for easy parsing and integration with behavioral analysis pipelines or synchronization with neurophysiological recordings (e.g., EEG time-locking).

## 🚀 Installation
1. Navigate to the [Releases] page of this repository.
2. Download the latest `.apk` file.
3. Transfer the APK to your Android device and install it (ensure "Install from unknown sources" is enabled in your device settings).

## 🛠 Core Architecture
* **`TrialRunner`**: Coroutine and `Handler` state machine managing the trial phases.
* **`StimulusRenderer`**: Custom `View` for rendering fixation and stimulus matrices.
* **`DataCollector`**: Handles the JSON logging and persistence.
* **`MainActivity`**: UI wrapper for the renderer, response buttons, progress display, and export screens.

## 📝 Citation & Contact
The manuscript is at the verge of acceptance, will add citation soon
