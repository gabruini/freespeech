# Freewrite

A native macOS video journaling app. Record short videos, get automatic transcriptions, and use AI to improve your language skills — all stored locally on your Mac.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.0-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## What it does

**Record → Transcribe → Analyze.**

1. Hit the camera button, speak, stop.
3. Run **Analyze** to get a high-accuracy transcript (ElevenLabs), pronunciation scoring (Azure), grammar corrections, and AI language coaching (Claude) — all in one step.

All data stays on your Mac under `~/Documents/Freespeech/`.

---

## Requirements

- **macOS 14.0** or later
- **Xcode 15** or later
- API keys to unlock AI features (see [Setup](#setup))

---

## Setup

### 1. Clone and open

```bash
git clone https://github.com/gabruini/freespeech.git
cd freespeech
open freespeech.xcodeproj
```

### 2. Build and run

Select the `freespeech` scheme and press **⌘R**. Or from the terminal:

```bash
xcodebuild -project freespeech.xcodeproj -scheme freespeech -configuration Debug build
```

### 3. Grant permissions

On first launch the app requests:
- **Camera** — to record video
- **Microphone** — to capture audio
- **Speech Recognition** — for live transcription

### 4. Add API keys

Open **Settings** (gear icon, bottom-right) or go through the onboarding flow. Keys are stored in the macOS Keychain.

#### Anthropic (Claude)
Used for AI language coaching and video analysis.
- Get a key at [console.anthropic.com](https://console.anthropic.com)

#### Microsoft Azure Speech
Used for pronunciation assessment, TTS synthesis, and word-timing extraction.
- Create a **Speech** resource in the [Azure Portal](https://portal.azure.com)
- You need the **Key** and the **Region** (e.g. `eastus`)

#### ElevenLabs
Used for high-accuracy audio transcription (`scribe_v2` model).
- Get a key at [elevenlabs.io](https://elevenlabs.io)

> **Note:** Recording work without any API keys. The **Analyze** pipeline and **Language Coach** require all three keys.

---

## License

MIT — see [LICENSE](LICENSE).
