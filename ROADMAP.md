# Momentary — Roadmap

## What Is Momentary?

Forked from [WristAssist](https://github.com/realworldbuilder/wristassist) (a simple voice notes app). Transformed into a **wrist-first workout notebook** where you start a strength training session on Apple Watch, record short voice "Moments" during the workout, and get AI-generated structured logs, social content, and training insights when the workout ends.

- **iOS 18 / watchOS 11** minimum (uses `@Observable`)
- **WhisperKit** for on-device transcription (bundled Whisper tiny model)
- **OpenAI GPT-4o** for AI processing (bundled API key via XOR obfuscation)

---

## Implementation Status

### Phase 1: Foundation — COMPLETE
All data models, persistence, and connectivity layers built from scratch.

| Step | Status | Files |
|------|--------|-------|
| Fork & rename (WristAssist -> Momentary) | DONE | pbxproj, schemes, bundle IDs |
| Data models | DONE | `Shared/Models.swift` |
| Persistence (directory-per-workout) | DONE | `Shared/WorkoutStore.swift` |
| Connectivity constants | DONE | `Shared/ConnectivityConstants.swift` |
| Phone connectivity (stripped, callback-based) | DONE | `Momentary/PhoneConnectivityManager.swift` |
| Watch connectivity (file transfer + metadata) | DONE | `Watch App/WatchConnectivityManager.swift` |
| Per-moment audio recording | DONE | `Watch App/AudioRecorderService.swift` |
| iOS orchestrator | DONE | `Momentary/WorkoutManager.swift` |
| watchOS orchestrator | DONE | `Watch App/WatchWorkoutManager.swift` |
| App entry points | DONE | `MomentaryApp.swift`, `MomentaryWatchApp.swift` |

### Phase 2: Watch-First UX — COMPLETE
Full workout lifecycle on Apple Watch + iPhone views.

| Step | Status | Files |
|------|--------|-------|
| Watch root navigation | DONE | `Watch App/Views/WatchRootView.swift` |
| Watch home (start workout + history) | DONE | `Watch App/Views/WatchHomeView.swift` |
| Active workout (timer, record, end) | DONE | `Watch App/Views/ActiveWorkoutView.swift` |
| Workout summary | DONE | `Watch App/Views/WorkoutSummaryView.swift` |
| iPhone tab view | DONE | `Momentary/Views/MainTabView.swift` |
| iPhone home (start + history) | DONE | `Momentary/Views/HomeView.swift` |
| Active workout tab (phone mirror) | DONE | `Momentary/Views/ActiveWorkoutTab.swift` |
| Workout detail (log + content + insights) | DONE | `Momentary/Views/WorkoutDetailView.swift` |
| Insights tab (cross-workout stories) | DONE | `Momentary/Views/InsightsTab.swift` |
| Settings (API key) | DONE | `Momentary/Views/SettingsView.swift` |

### Phase 3: HealthKit Integration — COMPLETE
Strength training sessions sync to Apple Health.

| Step | Status | Files |
|------|--------|-------|
| HealthKit service (HKWorkoutSession + builder) | DONE | `Shared/HealthKitService.swift` |
| Entitlements + Info.plist keys | DONE | pbxproj build settings |
| Wired into both orchestrators | DONE | `WorkoutManager.swift`, `WatchWorkoutManager.swift` |

### Phase 4: AI Processing — COMPLETE
OpenAI GPT-4o generates structured workout logs, social content, and insights.

| Step | Status | Files |
|------|--------|-------|
| AI backend protocol + OpenAI implementation | DONE | `Momentary/AIProcessingService.swift` |
| Prompt construction | DONE | `Momentary/AIPromptBuilder.swift` |
| Processing pipeline (offline queue, retry) | DONE | `Momentary/AIProcessingPipeline.swift` |
| Bundled API key (XOR obfuscation) | DONE | `Momentary/APIKeyProvider.swift` |

### Phase 5: Polish & Deliverables — COMPLETE

| Step | Status | Files |
|------|--------|-------|
| Legacy data migration | DONE | `WorkoutStore.migrateFromLegacyTranscriptions()` |
| README | DONE | `README.md` |
| App Store text | DONE | `AppStoreText.md` |

---

## What's Next: Testing & Bug Fixing

The full codebase has been written but has **not yet been compiled or tested**. The next session should focus on:

### Priority 1: Get It Compiling
- Open in Xcode, build both targets (iOS + watchOS)
- Fix any compile errors (likely cross-file resolution issues, missing imports, type mismatches)
- Resolve any Swift concurrency / Sendable warnings

### Priority 2: Core Workout Flow (Watch)
- Start workout on watch
- Record 3+ voice moments
- Verify audio files are created per-moment
- Verify audio transfers to iPhone via WCSession
- Verify WhisperKit transcribes audio on phone
- Verify transcription text sent back to watch
- End workout, verify summary screen

### Priority 3: Core Workout Flow (iPhone)
- Start workout on iPhone directly
- Record moments using phone mic
- End workout, verify session persists to disk
- Verify workout appears in history list
- Tap into workout detail view

### Priority 4: AI Processing
- End a workout with moments
- Verify OpenAI API call fires with bundled key
- Verify structured log, content pack, and insights parse correctly
- Verify they render in WorkoutDetailView
- Test offline queue (airplane mode -> end workout -> restore network)

### Priority 5: HealthKit
- Verify workout appears in Apple Health after ending
- Verify HealthKit authorization prompt

### Priority 6: Cross-Device Sync
- Start on watch, verify phone shows active state
- Record moments from both devices
- End from either side

### Priority 7: Edge Cases
- Kill app mid-workout, relaunch, verify state
- Empty workout (no moments), end gracefully
- Very long moments (60s+ recording)
- Network errors during AI processing (verify retry/queue)

---

## File Map (28 Swift files)

```
Momentary/
├── Shared/                              (4 files — both targets)
│   ├── ConnectivityConstants.swift
│   ├── Models.swift
│   ├── WorkoutStore.swift
│   └── HealthKitService.swift
├── Momentary/                           (13 files — iOS target)
│   ├── MomentaryApp.swift
│   ├── TranscriptionService.swift       (unchanged from WristAssist)
│   ├── PhoneConnectivityManager.swift
│   ├── PhoneAudioRecorderService.swift  (unchanged from WristAssist)
│   ├── WorkoutManager.swift
│   ├── AIProcessingService.swift
│   ├── AIPromptBuilder.swift
│   ├── AIProcessingPipeline.swift
│   ├── APIKeyProvider.swift
│   └── Views/
│       ├── MainTabView.swift
│       ├── HomeView.swift
│       ├── ActiveWorkoutTab.swift
│       ├── WorkoutDetailView.swift
│       ├── InsightsTab.swift
│       └── SettingsView.swift
└── Momentary Watch App/                 (9 files — watchOS target)
    ├── MomentaryWatchApp.swift
    ├── AudioRecorderService.swift
    ├── WatchConnectivityManager.swift
    ├── ExtendedSessionManager.swift     (unchanged from WristAssist)
    ├── WatchWorkoutManager.swift
    └── Views/
        ├── WatchRootView.swift
        ├── WatchHomeView.swift
        ├── ActiveWorkoutView.swift
        └── WorkoutSummaryView.swift
```

## Key Architecture Decisions

- **`@Observable`** (not `@StateObject`) for all managers — injected via `.environment()`
- **Directory-per-workout** storage: `Documents/workouts/<UUID>/session.json`
- **Callback closures** on connectivity managers (not owning business logic)
- **Offline AI queue** at `Documents/pending_ai_queue.json`
- **XOR-obfuscated bundled API key** — Keychain override available in Settings
- **Bundle IDs**: `com.whussey.momentary` (iOS), `com.whussey.momentary.watchkitapp` (watchOS)
- **Dev team**: `R2C4T4N7US`
