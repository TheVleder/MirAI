# MirAI — On-Device Voice AI for iPhone

> A fully local, privacy-first conversational AI that runs 100% on your iPhone. No cloud. No APIs. No data leaves your device.

---

## ✨ Features

### 🧠 On-Device LLM
- Runs **MLX-accelerated** language models natively on Apple Silicon (A17 Pro+)
- Models downloaded in-app from HuggingFace — **not bundled** in the binary
- **5 recommended models** picker (Qwen, Llama, Gemma, SmolLM2) or custom ID
- Switch/download/delete models directly from Settings
- App weighs **< 50 MB** before model download

### 🎤 Full-Duplex Voice
- **Push-to-Talk** or **Hands-Free** listening modes
- **Barge-in**: Interrupt the AI mid-sentence by speaking — it stops immediately and listens
- **Voice Activity Detection (VAD)**: Detects when you stop talking to auto-submit
- On-device Speech-to-Text via Apple Speech framework
- **Streaming TTS**: AI speaks sentence-by-sentence as it generates — no waiting for full response

### ⌨️ Text Input
- Type messages when you can't speak (noisy environments, meetings)
- Auto-expanding text field with send button
- Works alongside voice controls

### 🗣️ Text-to-Speech
- Multiple TTS voices grouped by quality tier (Default / Enhanced / Premium/Siri)
- **Voice preview** — tap ▶ to hear any voice before selecting
- Auto-selects best available voice on your device
- **Speech speed slider** (80%–150%) in Settings
- **Audio ducking** — background music auto-lowers during AI speech

### 🌍 Multi-Language Support
- In-chat language picker: **English 🇬🇧**, **Español 🇪🇸**, **Русский ��🇺**
- Switching language changes STT locale, TTS voice, and LLM response language
- Persisted across sessions

### 🎭 Personalities
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
| ➕ **Custom** | Create your own persona with custom prompts |

### 🔮 Animated Voice Orb
- Futuristic pulsing orb reacts to audio level in real-time
- Rotating arcs, glow rings, and state-reactive colors
- Red = listening, Cyan = speaking, Orange = processing, Idle = breathing

### 💡 Conversation Templates
- Quick-start prompts appear on empty conversations
- Templates change based on active personality
- Tap to instantly start a themed conversation

### 🧠 Memory System
- AI remembers facts about you across conversations
- Persistent via SwiftData (UserMemory model)
- Memory facts injected into LLM system prompt
- View and delete memories in Settings

### ✏️ Editable Transcriptions & Markdown
- Tap any message to edit the transcription in-line
- Edited messages auto-resend to the LLM for a corrected response
- **Markdown rendering**: bold, italic, code blocks rendered natively

### 💬 Conversation History
- **SwiftData** persistence — conversations survive app restarts
- Create, rename, delete conversations
- Search across all conversations and message content
- **Smart auto-titling** — LLM generates concise titles after first exchange
- Export/share conversations as formatted text
- **End Conversation** button — fully stops mic, TTS, and returns to list

### 📲 Onboarding
- 3-screen first-launch tutorial (Welcome → Personalities → Start Talking)
- Skip button for power users

### 🎙️ Siri Shortcuts
- "Hey Siri, ask MirAI" — opens the app and starts listening
- Powered by AppIntents framework

### 📳 Haptic Feedback
- Tactile feedback on every voice state change (listening, speaking, idle)
- Premium feel on mic button interactions

### 🔔 Daily Reminders
- Optional daily notification at 9 AM
- Motivational messages to encourage usage
- Toggle on/off in Settings

### 🔒 Background Audio & Privacy
- AI stays alive when screen locks or you switch apps
- **Zero network usage** after model download
- All processing happens **on-device**
- No analytics, no telemetry, no tracking

---

## 📱 Architecture

```
Sources/
├── Models/
│   ├── AppLanguage.swift          EN / ES / RU enum
│   ├── Conversation.swift         SwiftData model
│   ├── CustomPersonality.swift    User-created personas (SwiftData)
│   ├── Message.swift              SwiftData model
│   ├── Personality.swift          8 built-in AI personas
│   └── UserMemory.swift           Persistent memory facts (SwiftData)
├── Core/
│   ├── AudioManager.swift         STT + TTS + VAD + barge-in + streaming queue
│   ├── LLMManager.swift           MLX model lifecycle + streaming + memory
│   ├── ConversationManager.swift  CRUD + memory CRUD
│   ├── ModelDownloader.swift      HuggingFace download + 5 recommended models
│   ├── NotificationManager.swift  Daily reminder scheduling
│   └── SiriShortcuts.swift        AppIntents + shortcuts
├── Views/
│   ├── ContentView.swift          Root router (Onboarding → Download → Chat)
│   ├── OnboardingView.swift       3-screen first-launch tutorial
│   ├── DownloadView.swift         Model download UI
│   ├── ConversationListView.swift Conversation inbox + search
│   ├── ChatView.swift             Voice + text chat + templates + orb
│   ├── VoiceOrb.swift             Animated futuristic voice orb
│   ├── SettingsView.swift         Persona, voice, speed, model, memory, notifications
│   └── CustomPersonaEditorView.swift  Custom persona builder
└── MirAIApp.swift                 Entry point + SwiftData container
```

**Stack**: SwiftUI · MLX Swift · SwiftData · AVFoundation · Speech · AppIntents · UserNotifications

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
