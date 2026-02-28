# MirAI — Voice-to-Voice On-Device AI

> 🎙️ A fully local, privacy-first AI voice assistant for iPhone. Speak → Think → Respond — no internet after the initial model download.

---

## Architecture

```
┌─────────────────────────────────────────┐
│              MirAI (SwiftUI)            │
├──────────┬──────────┬───────────────────┤
│ Download │   Chat   │   ContentView     │
│  View    │   View   │   (Router)        │
├──────────┴──────────┴───────────────────┤
│              Core Layer                 │
├──────────┬──────────┬───────────────────┤
│  Model   │   LLM    │     Audio         │
│Downloader│  Manager │    Manager        │
│(Hub DL)  │(MLX Chat)│ (STT + TTS)       │
├──────────┴──────────┴───────────────────┤
│          Apple Frameworks               │
│ mlx-swift-lm │ Speech.framework │ AVF   │
└─────────────────────────────────────────┘
```

## Tech Stack

| Component | Technology | Details |
|-----------|-----------|---------|
| **UI** | SwiftUI | iOS 17+, Swift 6, dark mode |
| **LLM Engine** | [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 100% on-device via Metal/ANE |
| **Model** | Qwen2.5-1.5B-Instruct-4bit | ~1 GB, downloaded on first launch |
| **STT** | Speech.framework | `requiresOnDeviceRecognition = true` |
| **TTS** | AVFoundation | `AVSpeechSynthesizer` |
| **CI/CD** | GitHub Actions + Codemagic | Unsigned IPA for AltStore |

## Project Structure

```
MirAI/
├── Sources/
│   ├── MirAIApp.swift              # App entry point
│   ├── Info.plist                  # Permissions
│   ├── Core/
│   │   ├── ModelDownloader.swift   # HuggingFace model download
│   │   ├── LLMManager.swift       # MLX chat engine
│   │   └── AudioManager.swift     # STT + TTS pipeline
│   └── Views/
│       ├── ContentView.swift       # Router (download ↔ chat)
│       ├── DownloadView.swift      # Model download UI
│       └── ChatView.swift          # Voice chat interface
├── project.yml                     # XcodeGen definition
├── codemagic.yaml                  # Codemagic CI/CD
├── .github/workflows/
│   └── ios-build.yml               # GitHub Actions CI/CD
└── README.md
```

## Prerequisites

1. **iPhone 15 Pro** (or any A14+ device with iOS 17+)
2. **AltStore** or **Sideloadly** installed on your PC
3. **GitHub account** (for CI/CD builds)

## How to Build

### 1. Push to GitHub
```powershell
cd MirAI
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/MirAI.git
git push -u origin main
```

### 2. Download IPA
1. Go to your repo → **Actions** tab.
2. Wait for the **"Build MirAI iOS IPA"** workflow to complete (~5-10 min).
3. Download the **MirAI-unsigned** artifact (ZIP containing the IPA).

### 3. Install via AltStore
1. Extract `MirAI.ipa` from the downloaded ZIP.
2. Connect your iPhone to your PC with **AltServer** running.
3. Open **AltStore** on your iPhone → **My Apps** → **+** → select the IPA.
4. Sign in with your Apple ID (valid for 7 days with free account).

## First Launch

1. **Download Screen**: Tap "Download Model" → wait for ~1 GB download.
2. **Chat Screen**: Once downloaded, the model loads into memory.
3. **Talk**: Press and hold the mic button → speak → release → AI responds with voice.
4. **Next launches**: Model is cached — goes straight to the chat screen.

## Privacy

- 🔒 **Zero network calls** after model download
- 🎤 **On-device speech recognition** (no audio leaves the phone)
- 🧠 **On-device inference** via Apple's MLX framework
- 📵 **Works in airplane mode** (after initial setup)

## Fallback CI/CD (Codemagic)

If you hit GitHub Actions quota limits, push the repo to Codemagic:
1. Sign up at [codemagic.io](https://codemagic.io)
2. Connect your GitHub repository
3. The `codemagic.yaml` file will be automatically detected
4. Builds use M2 runners (500 free minutes/month)

## License

MIT
