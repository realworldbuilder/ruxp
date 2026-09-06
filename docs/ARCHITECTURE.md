# RUXP architecture

RUXP is the Momentary workout engine with a new product layer. This document covers the seams that were built for later and what a real backend replaces.

## Product loop

OPEN → SEE WHAT'S HAPPENING → START WORKOUT → EARN XP → SEE OTHER PEOPLE TRAINING → FINISH → COME BACK

Every screen maps to one step. If a feature does not improve the loop it is not built.

## Services

### ProgressionService (`Shared/RUXP/ProgressionService.swift`)
Single source of truth for XP. `@Observable @MainActor`, persisted at `Documents/player_progress.json`.

- `rewardWorkoutCompletion(session:events:)` runs synchronously when a workout ends. It never depends on network or the OpenAI key. Awards, in order: workout complete, event bonus (one per event occurrence), weekly bonus (4th workout of the ISO week).
- `rewardPersonalRecords(workoutID:count:)` runs later, when the AI pipeline parses the voice notes and `InsightsStore.ingest` returns improved records. It appends to `lastReward` so an open completion screen animates the new row in.
- Rules live in `ProgressionRules` (minimum duration, daily cap, PR cap). Idempotency is persisted (`rewardedWorkoutIDs`, `prRewardsByWorkout`, `weeklyBonusWeeks`, `eventsJoined`).
- `rebuild(from:events:)` replays history for upgrades and the sample-data loader.

Level is seasonal (`LevelCurve.progress(seasonXP:)`), lifetime XP is a career total. A season rollover zeroes season XP on first launch inside the new season.

### LiveEventProviding (`Shared/RUXP/LiveEvents.swift`)
"What is happening right now?" `ScheduledEventService` computes FRIDAY NIGHT (Fri 17:00–24:00, +500) and SUNDAY RESET (Sun, +250) from the clock, plus the season-wide BACK 2 SCHOOL theme. `featuredEvent(at:)` returns live → next → season.

A backend implementation returns gym-hosted or brand events from the server with the same shape: title, description, start, end, xpReward, participant count.

### LivePresenceProviding (`Shared/RUXP/LivePresence.swift`)
"Who is training right now?" `SimulatedLivePresence` is demo data: a time-of-day curve plus a random walk. `LiveSnapshot.isDemo` is true. Replace with a real-time provider (WebSocket, Firestore, etc.) and inject via `\.livePresence`. The watch runs its own instance with a slower tick.

## Phone ↔ watch

`WorkoutMessage` (`Shared/Models.swift`) carries commands over WatchConnectivity. RUXP adds:

- `WorkoutCommand.workoutReward` with `xpEarned`, `level`, `levelUp`, `prCount`. Sent by the phone after any end (phone- or watch-initiated) and again when PR XP lands. Falls back to `transferUserInfo` when unreachable.
- Application-context keys `ctx_level`, `ctx_seasonXP`, `ctx_xpIntoLevel`, `ctx_xpToNext` (`ProgressionContext`), merged into every context update so the watch home can show "LVL 12" cold.

The watch never computes XP. It shows "Syncing XP" → "+1,000 XP · LVL 13", or "XP syncs on iPhone" when unreachable.

## Presentation

`MainTabView` hosts one `fullScreenCover` (`WorkoutFlowCover`) that shows `ActiveWorkoutTab` while a session is active and `WorkoutCompletionSheet` once `completedWorkoutID` is set. `WorkoutManager` sets `completedWorkoutID` **before** clearing `activeSession` so the cover crossfades instead of dismissing. CONTINUE clears `completedWorkoutID` and returns to Home.

## What is hidden, not deleted

The Momentary-era AI trainer chat, insights tab, story carousel, and social content generation still compile but are not reachable from navigation (`ChatView`, `InsightsTab`, `InsightStoryView`, `StoryCarouselView`, `TrainerSoulEditor`). `contentPack` is no longer persisted. The AI pipeline is kept for what matters: turning voice notes into exercises, sets, reps, weight, and PRs.

## Later (not built)

Real-time backend, friends, squads, gym profiles, gym-hosted events, brand rewards, leaderboards, remote gym experiences, push notifications. Each plugs into one of the protocols above or into `PlayerProgress`. None of them are speculatively wired.
