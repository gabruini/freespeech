# Freespeech - Technical Documentation

## Product Vision & User Experience

### What is Freespeech?

Freespeech is a **video journaling app** for macOS. Users record short videos, the app automatically transcribes them, and it can then run grammar checks, pronunciation assessment, AI language coaching, and full video analysis on the transcript. All data stays local.

### Use Cases

**Primary Use Case — Video Journaling:**
- One-click record, automatic transcription in the user's chosen language
- Local storage for privacy
- History
- Each recording's media and metadata live under `~/Documents/Freespeech/`

**Secondary Use Case — Language Learning:**
- Pick a target language from the language picker
- Speak in that language; the app transcribes with speech recognition
- Grammar check via LanguageTool, pronunciation assessment via Azure Speech, AI coaching via Claude, video analysis via ElevenLabs + Azure + Claude

## Overview

Native macOS SwiftUI app. All data stored locally in `~/Documents/Freesppech/`. No text-editor mode — the app is video-only.

## Architecture

### Technology Stack
- **Framework**: SwiftUI (macOS)

- **Minimum macOS Version**: 14.0

- **Language**: Swift 5.0

- **Build System**: Xcode

- **Media**: AVFoundation for camera/video recording

  

## Data Model

### Entry

```swift
struct HumanEntry: Identifiable {
    let id: UUID
    let date: String              // Display format: "MMM d" (e.g., "Feb 20")
    let filename: String          // Format: [UUID]-[YYYY-MM-DD-HH-mm-ss].md  (metadata sibling)
    let videoFilename: String     // Format: [UUID]-[YYYY-MM-DD-HH-mm-ss].mov
    var languageCode: String?     // BCP-47 locale of the recording language
}
```

Every entry is a video entry. The `.md` sibling holds a literal `"Video Entry"` string and serves as the canonical enumeration pivot when the app scans the Documents directory on launch.

### File Storage

**Location**: `~/Documents/Freespeech/`

**Per-entry layout** (current):
```
~/Documents/Freewrite/
  [UUID]-[YYYY-MM-DD-HH-mm-ss].md                               # metadata sibling
  Videos/
    [UUID]-[YYYY-MM-DD-HH-mm-ss]/
      [UUID]-[YYYY-MM-DD-HH-mm-ss].mov                          # the recording
      thumbnail.jpg                                              # cached thumbnail
      transcript.md                                              # optional; YAML front-matter + text
      pronunciation.json                                         # optional; per-word confidences
      pronunciation-assessment.json                              # optional; Azure result
      grammar.json                                               # optional; LanguageTool result
      word-timings.json                                           # optional; Azure TTS word-level timing
      analysis/                                                  # optional; video analysis output
```

**Legacy video layouts** (still supported for read):
- `~/Documents/Freespeech/Videos/[entry-base].mov` (flat Videos dir)
- `~/Documents/Freespeech/[entry-base].mov` (flat root dir)

`hasVideoAsset(for:)` and `getVideoURL(for:)` probe the three locations in order.

**Legacy text `.md` files**: users migrating from earlier writing-oriented releases may have text-only `.md` files without a paired `.mov`. Those files are **preserved on disk** but **hidden from the UI** — `loadExistingEntries()` skips any `.md` that does not resolve to a video asset.

## Key Components

### ContentView.swift

Main view. Hosts the entries array, current selection, and the video player / empty-state area. No text editing.

#### Selected State Variables

```swift
@State private var entries: [HumanEntry] = []
@State private var selectedEntryId: UUID? = nil
@State private var currentVideoURL: URL? = nil
@State private var showingVideoRecording = false
@State private var selectedVideoHasTranscript = false
@State private var showingSidebar = false
@State private var colorScheme: ColorScheme = .light
@AppStorage("targetLanguageCode") private var targetLanguageCode: String = "en-US"
```

Pronunciation, grammar, AI coach, and video-analysis state all hang off the currently-selected video entry and reset in `loadEntry(entry:)`.

#### Core Functions

- `loadExistingEntries()` — scans `~/Documents/Freespeech/`, includes only `.md` files whose paired `.mov` exists, sorts newest-first, selects the first entry (or leaves `selectedEntryId` nil for the empty state).
- `loadEntry(entry:)` — loads the video, thumbnail, transcript, pronunciation data, grammar, cached analysis; resets per-entry state.
- `deleteEntry(entry:)` — deletes the `.md` and the per-entry video directory (including all auxiliary files); selects the new first entry or falls back to the empty state.
- `saveVideoEntry(from:transcript:wordConfidences:)` — called when the recorder finishes. Writes the `.mov` + `.md` metadata + transcript + thumbnail + pronunciation JSON, inserts the new `HumanEntry` at the top of `entries`, and kicks off auto-analysis if a transcript is present.

**Threading rule**: any mutation of `entries` from a non-main thread must be dispatched to main. `saveVideoEntry` uses `if Thread.isMainThread { ... } else { DispatchQueue.main.async { ... } }`.

### VideoRecordingView.swift

Handles camera + microphone capture, live speech recognition, and transcript finalization. Presented as an edge-to-edge overlay over `ContentView` with animations disabled on open/close.

#### CameraManager

```swift
class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: Int = 0
    @Published var permissionGranted = false
    @Published var microphonePermissionGranted = false
    @Published var speechPermissionGranted = false
    var speechLocale: Locale
}
```

Owns an `AVCaptureSession` (video + audio), an `AVCaptureMovieFileOutput`, and an `AVCaptureAudioDataOutput` that streams buffers to `SFSpeechAudioBufferRecognitionRequest`.

### VideoPlayerView.swift

AVKit-based player with a `isPlaybackSuspended` binding so playback pauses while the recorder overlay is opening or showing.

## UI Layout

### Main interface

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│    Video Player (when an entry is selected)              │
│               OR                                         │
│    Empty state ("No recordings yet / Tap the camera…")   │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  Bottom nav (left: tools) · (right: utilities)     │
└──────────────────────────────────────────────────────────┘
```



## Video Recording Flow

1. User clicks the camera button.
2. Icon switches to a small spinner while `startVideoRecordingPreflight()` runs.
3. App requests/validates **camera + microphone**.
4. If any permission is missing, the recorder is not presented; a compact popover lists what's missing and links to System Settings.
5. When the session is ready, a short presentation delay elapses and `VideoRecordingView` is presented via `.overlay` with animations disabled.
6. Camera preview fills the window edge-to-edge. A transparent bottom nav shows Close, recording status, Start/Stop control, and the elapsed timer.
7. On Start: recording begins to a temp file, speech transcription starts, timer counts up.
9. `saveVideoEntry(from:transcript:wordConfidences:)` creates `~/Documents/Freespeech/Videos/[UUID]-[date]/`, moves the video into it, writes `thumbnail.jpg`, `transcript.md` (with YAML front-matter carrying the language code), and `pronunciation.json` if confidences are present. It also writes the `.md` metadata sibling in the Documents root.
10. The new entry is inserted, selected, and the video plays automatically. 
11. If the user hits Close mid-recording, the temp file is discarded; no entry is created.

## Video Playback Flow

1. User selects an entry in the sidebar.
2. `loadEntry(entry:)` resolves the `.mov`, thumbnail, transcript URLs, loads cached grammar/pronunciation/assessment data, and sets `currentVideoURL`.
3. The main area switches to `VideoPlayerView`. `Copy Transcript` and the analysis buttons populate based on what's cached.

## Analyze Pipeline

`VideoAnalysisService.run` is the single place where high-quality STT and downstream analysis happen. Steps:

1. `.extractingAudio` — AVFoundation locally converts `.mov` to 16 kHz mono WAV.
2. `.transcribing` — ElevenLabs `scribe_v2` returns the transcript. The raw JSON is saved to `eleven-transcript.json` and **`transcript.md` is overwritten** with the new text (YAML front-matter preserved with the current language). This keeps Copy Transcript, sidebar preview, Chat, and Grammar aligned to the most accurate transcript available.
3. `.analyzing` — runs **two calls in parallel**:
   - **Claude (`claude-sonnet-4-6`)** produces the analysis JSON (`summary`, `errors`, `phrasal_verbs`, `better_phrasings`, `corrected_text`) saved to `analysis.json` + `corrected.txt`.
   - **Azure Pronunciation Assessment** (best-effort) scores the transcript against the audio, saving to `pronunciation-assessment.json`. Failures here do not block Analyze.
4. `.synthesizing` — **Azure TTS** renders `corrected.mp3`, then Azure STT is run on the TTS audio to extract word-level timing saved to `word-timings.json`. This timing drives real-time subtitle sync during playback.
5. `.done` — `ContentView`'s `.onChange(of: videoAnalysisService.phase)` picks this up and refreshes per-entry state: reloads `currentAssessmentResult`, refreshes `selectedVideoHasTranscript`, and re-runs Grammar (LanguageTool) on the new transcript (re-run is local and free, so it's always safe).

## Permissions

Required entitlements in `freewrite.entitlements`:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.personal-information.speech-recognition</key>
<true/>
```

Privacy usage descriptions (in Xcode project build settings):

```
INFOPLIST_KEY_NSCameraUsageDescription = "Freespeech needs camera access to record video entries."
INFOPLIST_KEY_NSMicrophoneUsageDescription = "Freespeech needs microphone access to record audio with your video entries."
```

## Technical Nuances

### Threading Model

- **Main Thread**: all UI and `@State` mutations.
- **Global Queue**: file I/O.
- **AVFoundation Queue**: camera setup and capture.

`saveVideoEntry`'s `selectNewVideoEntry` closure is dispatched to main if not already there, because it mutates `entries` which SwiftUI's `ForEach` enumerates.

### File-name parsing

`parseCanonicalEntryFilename` expects `[UUID]-[YYYY-MM-DD-HH-mm-ss].md` exactly. Anything else is ignored — this guarantees legacy or user-introduced files can't corrupt the sidebar.

### Thumbnail generation

Thumbnails are generated once at save time from the `.mov` and persisted as `thumbnail.jpg` in the per-entry directory. `loadThumbnailImage(for:)` has an in-memory `NSCache` and a one-time generator for legacy entries that predate the `thumbnail.jpg` convention.

### Theme System

```swift
@State private var colorScheme: ColorScheme = .light
```

Persisted to `UserDefaults` under `"colorScheme"`.

Text colors:
- Light mode: `Color(red: 0.20, green: 0.20, blue: 0.20)` (dark gray)
- Dark mode: `Color(red: 0.9, green: 0.9, blue: 0.9)` (off-white)

### AVCaptureSession safety

```swift
captureSession?.beginConfiguration()
// add/remove inputs/outputs
captureSession?.commitConfiguration()
```

Do not mutate inputs/outputs while the session is running. Avoid duplicate `checkPermissions()` and duplicate `startRunning()` for the same presentation.

### Legacy files

Never delete `.md` files that lack a paired `.mov` — those are legacy text entries from earlier releases. Hide them in `loadExistingEntries` but leave them untouched on disk.

## Build Configuration

**Scheme**: freespeech
**Build command**:

```bash
xcodebuild -project freespeech.xcodeproj -scheme freespeech -configuration Debug build
```

**Clean build**:
```bash
xcodebuild -project freespeech.xcodeproj -scheme freespeech -configuration Debug clean build
```

## Testing the video feature

1. Build and run.
2. Grant camera/microphone permissions on first use.
3. Click the camera button — spinner → recorder overlay.
4. Start Recording, speak for a few seconds, Stop Recording.
5. Overlay closes, the new entry is selected, and the video plays immediately.
6. Open the sidebar to confirm the entry is there with thumbnail, language flag, and the first few transcript words as preview.
7. With the entry selected, try Copy Transcript, Check Grammar, Pronunciation (if assessed), Language Coach (if Anthropic key set), and Analyze (if ElevenLabs + Azure + Anthropic keys set).

## Feature Flags / Settings

`UserDefaults`:
- `colorScheme`: "light" or "dark"
- `targetLanguageCode`: BCP-47 locale (stored via `@AppStorage`)

Keychain (via `KeychainHelper`):
- ElevenLabs key (`VideoAnalysisService.elevenLabsKeyKeychainKey`)
- Azure Speech key + region (used for TTS, pronunciation assessment, word timing)
- Anthropic API key (`VideoAnalysisService.anthropicKeyKeychainKey`)

## Summary

Freewrite is a video-only journaling app. The one data type is `HumanEntry` backed by a video + metadata pair. The main complexity is:

1. Coordinating permissions (camera + microphone) before presenting the recorder.
2. Thread-safe array mutation in `saveVideoEntry`.
3. AVCaptureSession lifecycle with `beginConfiguration` / `commitConfiguration`.
4. Per-entry caches (thumbnail, transcript, grammar, pronunciation, analysis).

When making changes, always:
- Build with `xcodebuild`.
- Test an actual recording end-to-end.
- Verify `~/Documents/Freespeech/` is laid out as expected.
- Confirm legacy text-only `.md` files remain untouched and hidden.
