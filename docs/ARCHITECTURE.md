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

Level is seasonal (`LevelCurve.progress(seasonXP:)`), lifetime XP is a career total. A season rollover zeroes season XP on first launch inside the new season. A stored `S01` from builds 1–3 is renamed to `S00` in place, keeping XP and remapping equipped reward IDs.

### LiveEventProviding (`Shared/RUXP/LiveEvents.swift`)
"What is happening right now?" `ScheduledEventService` computes FRIDAY NIGHT (Fri 17:00–24:00, +500) and SUNDAY RESET (Sun, +250) from the clock, plus the season-wide theme from `SeasonCatalog.current`. `featuredEvent(at:)` returns live → next → season.

A backend implementation returns gym-hosted or brand events from the server with the same shape: title, description, start, end, xpReward, participant count.

### LivePresenceProviding (`Shared/RUXP/LivePresence.swift`)
"Who is training right now?" Answered by Game Center recurring leaderboards, with no server. A recurring board's current occurrence reports `totalPlayerCount`: the players who submitted in that window.

- `active_a` / `active_b`: two 30-minute windows staggered by 15 minutes. `WorkoutManager` (and `WatchGameCenter` during a watch-run workout) pings both every 5 minutes while a workout is active. `liftingNow` is the max of the two, so it never dips to zero at a boundary.
- `trained_today`: 24-hour window, pinged on a rewarded completion. `workoutsToday`.
- `event_friday_night` / `event_sunday_reset`: weekly windows padded to cover every US time zone's local event. `participantCount(for:)`.
- `season_xp_*`: the classic season board's player count is "players this season".

`GameCenterLivePresence` (`RUXP/GameCenter/`) polls the six boards every 60 seconds in the foreground and immediately after our own pings. `LiveSnapshot.isAvailable` is false until sign-in and a successful poll; views show a sign-in line instead of numbers. The watch never polls: `MirroredLivePresence` takes the snapshot from the application context (`ctx_liftingNow`, `ctx_trainedToday`, `ctx_presenceAvailable`, `ctx_presenceUpdatedAt`) and shows "—" once it is older than 10 minutes.

### GameCenterService (`RUXP/GameCenter/GameCenterService.swift`)
Sign-in, XP leaderboards, achievements, presence pings. `ProgressionService.onProgressChanged` fires after every `save()`; the service debounces about 8 seconds so the completion award and the later PR bonus collapse into one submission. Scores are absolute totals (Game Center keeps the best), one leaderboard ID per call so an unconfigured board cannot block the others, with a persisted dirty flag retried on sign-in, foreground, and toggle. Achievements are reported only when the percent grows. On first sign-in a card still named PLAYER takes the Game Center alias. IDs live in `Shared/RUXP/GameCenterCatalog.swift`; each season needs its own `season_xp_*` and `season_goal_*` created in App Store Connect before it starts. Season 0 uses `season_xp_s00` / `season_goal_s00`. `-RUXPSkipGameCenter` (DEBUG) disables all of it.

### SeasonPassCatalog (`RUXP/SeasonPass/SeasonPassCatalog.swift`)
The free reward track. Twenty tiers for the current season, one cosmetic each (title, name color, badge); tier N is unlocked when `PlayerProgress.level >= N`, so there is no claim step and a season rollover relocks the ladder on its own. Pure functions of `PlayerProgress` + `Season`; nothing here writes XP. Equipped cosmetics live in `PlayerProgress.equippedCosmetics` (`[kind: rewardID]`, **Optional so older progress files decode**) and are written through `ProgressionService.setEquippedCosmetic(kind:rewardID:)`. `SeasonPassView` (Profile → Season Pass, or the Home season card) renders the ladder; `SeasonPassCatalog.loadout(for:season:)` is what Profile and the share card draw; `newlyUnlocked(from:to:season:)` feeds the tier-unlock rows on the reward screen. iOS target only. Permanence of Season 0 cosmetics across the Dec 1 rollover is a follow-up: `reward(id:)` must resolve any season's ladder and `PlayerProgress` needs an Optional `seasonsPlayed: [String: Int]?`.

## Phone ↔ watch

`WorkoutMessage` (`Shared/Models.swift`) carries commands over WatchConnectivity. RUXP adds:

- `WorkoutCommand.workoutReward` with `xpEarned`, `level`, `levelUp`, `prCount`. Sent by the phone after any end (phone- or watch-initiated) and again when PR XP lands. Falls back to `transferUserInfo` when unreachable.
- Application-context keys `ctx_level`, `ctx_seasonXP`, `ctx_xpIntoLevel`, `ctx_xpToNext` (`ProgressionContext`), merged into every context update so the watch home can show "LVL 12" cold.

The watch never computes XP. It shows "Syncing XP" → "+1,000 XP · LVL 13", or "XP syncs on iPhone" when unreachable.

## Presentation

`MainTabView` hosts one `fullScreenCover` (`WorkoutFlowCover`) that shows `ActiveWorkoutTab` while a session is active and `WorkoutCompletionSheet` once `completedWorkoutID` is set. `WorkoutManager` sets `completedWorkoutID` **before** clearing `activeSession` so the cover crossfades instead of dismissing. CONTINUE clears `completedWorkoutID` and returns to Home.

## Design system

`Theme.swift` (iOS) and `WatchTheme.swift` (watch) hold every token. The look is ChatGPT with hints of gaming: neutral near-black ground, flat surfaces with hairline borders, white pill buttons, system type for everything you read. The game shows up in small doses: Orbitron on the wordmark (with a one-pixel chromatic offset) and one hero number per screen, JetBrains Mono in terminal green for XP values, a magenta progress bar and tab tint, a red LIVE dot. Season 00 is "EARLY ADOPTERS"; Season 01, "PRESS START", follows on Dec 1.

Orbitron and JetBrains Mono (plus Exo 2, currently unused) ship in `Shared/Fonts` under the SIL Open Font License and are registered at launch by `Typeface.registerFonts()` (CoreText, no `UIAppFonts` entry). `Theme.Fonts.ui(_:weight:mono:)` wraps the system text styles and switches to the mono face for readouts. `HUDBackground` is the flat ground with an optional faint glow for the workout and reward screens.

## What is hidden, not deleted

The Momentary-era AI trainer chat, insights tab, story carousel, and social content generation still compile but are not reachable from navigation (`ChatView`, `InsightsTab`, `InsightStoryView`, `StoryCarouselView`, `TrainerSoulEditor`). `contentPack` is no longer persisted. The AI pipeline is kept for what matters: turning voice notes into exercises, sets, reps, weight, and PRs.

## Later (not built)

Friends and squads (Game Center friends scope is one flag away), gym profiles, gym-hosted events, brand rewards, a rank line on Home, per-lift and total-volume leaderboards (they depend on the OpenAI parse), remote gym experiences, push notifications. Each plugs into one of the protocols above or into `PlayerProgress`. None of them are speculatively wired.
