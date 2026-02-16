# Immediate Fixes Required for Momentary App

## Critical Issues to Address

### 1. Transcription Service Inconsistency
**File:** `Momentary/Momentary/TranscriptionService.swift`
**Problem:** Code uses OpenAI API for transcription, but documentation claims WhisperKit
**Fix Options:**
- A) Implement WhisperKit for on-device transcription as documented
- B) Update all documentation to reflect OpenAI API usage
**Recommendation:** Go with Option A for privacy benefits and offline capability

### 2. Bundle ID Standardization
**Files:** Project settings, documentation
**Problem:** Multiple bundle ID references:
- Documentation: `com.whussey.momentary`
- Roadmap: `com.momentary.app`
**Fix:** Choose one standard and update all references

### 3. Missing Dependencies Configuration
**Problem:** WhisperKit dependency mentioned but not visible in project
**Fix:** Verify SPM packages are properly added to project in Xcode

## Files Requiring Updates

### High Priority
1. `Momentary/Momentary/TranscriptionService.swift` - Replace with WhisperKit implementation
2. `ROADMAP.md` - Fix bundle ID references
3. `NEXT_SESSION_PROMPT.md` - Fix bundle ID references
4. Project settings - Verify bundle IDs match documentation

### Medium Priority
1. `AppStoreText.md` - Verify privacy claims match implementation
2. `Momentary/Momentary/Views/SettingsView.swift` - Update "WhisperKit" reference if keeping OpenAI

## Quick Wins (Can be fixed without Xcode)

### Fix Bundle ID References in Documentation
```bash
# Update ROADMAP.md
sed -i '' 's/com\.momentary\.app/com.whussey.momentary/g' ROADMAP.md
sed -i '' 's/com\.momentary\.app\.watchkitapp/com.whussey.momentary.watchkitapp/g' ROADMAP.md

# Update NEXT_SESSION_PROMPT.md  
sed -i '' 's/com\.momentary\.app/com.whussey.momentary/g' NEXT_SESSION_PROMPT.md
sed -i '' 's/com\.momentary\.app\.watchkitapp/com.whussey.momentary.watchkitapp/g' NEXT_SESSION_PROMPT.md
```

### Update Privacy Policy Links (if needed)
Verify that `realworldbuilder.github.io/momentary/` is correct or update to proper domain.

## Build Commands to Run (Once Xcode Available)

```bash
# Navigate to project
cd /Users/williamhussey/.openclaw/workspace/repos/momentary

# List all schemes
xcodebuild -project Momentary/Momentary.xcodeproj -list

# Build iOS target
xcodebuild -project Momentary/Momentary.xcodeproj \
  -scheme Momentary \
  -destination 'generic/platform=iOS' \
  clean build

# Build watchOS target  
xcodebuild -project Momentary/Momentary.xcodeproj \
  -scheme "Momentary Watch App" \
  -destination 'generic/platform=watchOS' \
  clean build
```

## Testing Checklist

### Phase 1: Compilation
- [ ] iOS target builds without errors
- [ ] watchOS target builds without errors  
- [ ] All dependencies resolve correctly
- [ ] No Swift concurrency warnings

### Phase 2: Core Functionality
- [ ] Start workout on watch
- [ ] Record voice moments
- [ ] Audio transfers to phone
- [ ] Transcription works (WhisperKit or OpenAI)
- [ ] End workout shows summary

### Phase 3: Integration
- [ ] HealthKit workout appears in Health app
- [ ] AI processing generates workout log
- [ ] Phone/watch connectivity sync works
- [ ] Offline mode functions properly

## App Store Prep Checklist

- [ ] Verify bundle IDs match App Store Connect
- [ ] Test on physical iPhone + Apple Watch
- [ ] Confirm privacy policy accuracy
- [ ] Test with TestFlight before production
- [ ] Ensure API key handling is disclosed appropriately