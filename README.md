# MirAI — On‑Device Voice AI for iPhone

> A fully local, privacy-first conversational AI that runs 100% on your iPhone. No cloud. No APIs. No data leaves your device.

---

## ✨ Features

### 🧠 On-Device LLM
- Runs **MLX-accelerated** language models natively on Apple Silicon (A17 Pro+)
- Models downloaded in-app from HuggingFace — **not bundled** in the binary
- Dynamic model selector — use any compatible `mlx-community` model
- App weighs **< 50 MB** before model download

### 🎤 Full-Duplex Voice
- **Push-to-Talk** or **Hands-Free** listening modes
- **Barge-in**: Interrupt the AI mid-sentence by speaking — it stops immediately and listens
- **Voice Activity Detection (VAD)**: Detects when you stop talking to auto-submit
- On-device Speech-to-Text via Apple Speech framework

### 🗣️ Text-to-Speech
- Multiple TTS voices with quality tiers (Default / Enhanced / Premium)
- Auto-selects the best available voice on your device
- Voice selector in Settings to pick your preferred voice

### 🎭 8 AI Personalities
| Persona | Style |
|---------|-------|
| 🤝 The Friend | Warm, casual, supportive |
| 🧑‍🍳 The Chef | Passionate about food and cooking |
| 🔬 The Scientist | Curious, precise, uses analogies |
| 🗳️ The Politician | Diplomatic, balanced, articulate |
| 🃏 Dark Humor | Witty, sardonic, irreverent |
| 🎭 The Poet | Lyrical, metaphorical, expressive |
| 💪 The Coach | Motivational, action-oriented |
| 🧠 The Philosopher | Deep thinker, questions everything |

### 💬 Conversation History
- **SwiftData** persistence — conversations survive app restarts
- Create, rename, delete conversations
- Search across all conversations
- Auto-titles from first message
- Per-conversation personality tracking

### 🔒 Background Audio
- AI stays alive when screen locks or you switch apps
- `UIBackgroundModes: audio` keeps mic and TTS active

### 📊 Download Experience
- Progress bar with percentage
- Download speed indicator (MB/s)
- File size display
- One-tap model deletion to free storage

---

## 📱 Architecture

```
Sources/
├── Models/
│   ├── Conversation.swift       SwiftData model
│   ├── Message.swift            SwiftData model
│   └── Personality.swift        8 AI personas
├── Core/
│   ├── AudioManager.swift       STT + TTS + VAD + barge-in
│   ├── LLMManager.swift         MLX model lifecycle + personalities
│   ├── ConversationManager.swift  CRUD operations
│   └── ModelDownloader.swift    HuggingFace download + speed tracking
├── Views/
│   ├── ContentView.swift        Root router
│   ├── DownloadView.swift       Model download UI
│   ├── ConversationListView.swift  Conversation inbox
│   ├── ChatView.swift           Voice chat interface
│   └── SettingsView.swift       Persona, voice, mode settings
└── MirAIApp.swift               Entry point + SwiftData container
```

**Stack**: SwiftUI · MLX Swift · SwiftData · AVFoundation · Speech · ActivityKit

---

## 🛠️ Build & Install

### Requirements
- Xcode 16+ (or Codemagic with Xcode 26+)
- iOS 17.0+ deployment target
- iPhone with A17 Pro or newer recommended

### Build locally
```bash
brew install xcodegen
xcodegen generate
xcodebuild build \
  -project MirAI.xcodeproj \
  -scheme MirAI \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO
```

### CI/CD
- **GitHub Actions**: Builds unsigned IPA on every push to `main`
- **Codemagic**: Fallback CI with Metal Toolchain support
- Download the `.ipa` artifact from the Actions tab

### Install via AltStore
1. Download the `.ipa` from GitHub Actions artifacts
2. Open AltStore on your iPhone
3. Tap **+** → select the `.ipa` → install
4. Launch MirAI → download a model → start talking

---

## 🔐 Privacy

- **Zero network usage** after model download
- All processing happens **on-device**
- Conversations stored locally via SwiftData
- No analytics, no telemetry, no tracking
- Microphone used only for voice input

---

## 📝 License

MIT
