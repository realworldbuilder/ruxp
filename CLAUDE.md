# CLAUDE.md — RUXP

RUXP is a social, live-feeling strength app for iPhone and Apple Watch. The Momentary voice-logged workout engine underneath; a product layer on top that makes the gym feel like something is happening right now. No backend: shared state comes from Game Center recurring leaderboards and the clock.

The loop, and the only reason any screen exists:

```
OPEN → SEE WHAT'S HAPPENING → START WORKOUT → EARN XP → SEE OTHER PEOPLE TRAINING → FINISH → COME BACK
```

Read next: `README.md` (product + XP rules), `docs/ARCHITECTURE.md` (services, what a backend replaces), `docs/PHILOSOPHY.md` (the full design philosophy this file condenses).

Season 00 EARLY ADOPTERS is live (Sep 1 – Sep 30, 2026, TestFlight; goal 12). Season 01 NIGHTMARE MODE (Oct 1 – Nov 30, 2026; goal 20) is the App Store launch season. Season 02 PRESS START starts Dec 1, 2026. Existing players have `player_progress.json` files on their phones: every change must decode them.

---

## The living product philosophy

RUXP is designed as a **world, not a tool**. A tool waits for the user. A world keeps moving without them. The standard for every screen:

> something is happening right now.
> something happened while you were gone.
> something new might happen tonight.

**Principles** (full text in `docs/PHILOSOPHY.md`):

1. Build a world, not just a tool: ask "what is happening here?", not only "what can the user do?"
2. Make time matter: Friday night is not Tuesday morning. The clock is part of the product.
3. Let the world move without me: design for return; absence is not dead time.
4. Season what benefits from seasons: chapters with real shifts, never renamed releases.
5. Change the rules, not only the content: ship rules instead of features.
6. Experiment in public: this weekend only; reversible over permanent.
7. Give users something to become: roles, artifacts, history, "this is mine".
8. Make progress visible: streaks, records, collections. Never gamify meaningless actions.
9. Reward showing up, sparingly and never punitively.
10. Create rituals, not just habits: "this is what we do."
11. Sides and allegiances when natural; belonging over leaderboards.
12. Design for conversation: what will one user tell another about today?
13. Let users bring something back: history should change the future experience.
14. "You had to be there" moments: impermanence for experience, never for core function.
15. Sell identity or belonging, never basic function.
16. Commerce as experience, never as pressure.
17. Collaborations change the product mechanically, not cosmetically.
18. Eventually let other people build.
19. Never completely finish: design anticipation, not chaos.

**The Aliveness Test.** Run it on every feature, screen, or flow before building. Do not maximize every score; find the opportunity.

1. What is happening right now?
2. What might happen later today?
3. What could happen while the user is gone?
4. Does Friday feel any different from Tuesday?
5. Is there anything to anticipate?
6. Is there anything to remember?
7. Can users develop an identity here?
8. Can users belong to something?
9. Does past participation affect the future?
10. Is there a reason to tell another person about what happened?
11. Could something temporarily change the rules?
12. Could this become a ritual?
13. Does this create genuine aliveness or merely more notifications?
14. Would someone ever return and say, "wait, what happened?"
15. Is there something happening now that won't simply wait forever?

**Cut list.** Not in RUXP: daily login rewards; streak-loss nagging; push notifications (none yet); inflated or invented presence; loot, crates, random rewards; paid XP or paid tiers; a permanent rank line on Home; "double XP every weekend" (it dilutes FRIDAY NIGHT); countdown timers on non-events; chat in rooms; arbitrary badges; renaming builds as seasons; anything that makes essential functionality temporary.

**How to respond to a product idea.** First check the core utility is good. Then analyze through: CORE LOOP · RIGHT NOW · WHILE YOU WERE GONE · RITUALS · SEASONS · LIVE MECHANICS · IDENTITY · PROGRESSION · COMMUNITY · "YOU HAD TO BE THERE" · WORLD BUILDING · CUT THE BULLSHIT. End with a prioritized recommendation: the 1–3 mechanics that transform the product, smallest version first. Never propose 30 features.

**Where RUXP stands (Sep 2026).** Right now: real lifting-now count, a crew member lifting right now, featured ritual card, LIVE dot, the Home clock line. While you were gone: `WorldSnapshotService` return ledger, including who in your crew showed up. Rituals: FRIDAY NIGHT (Fri 5 PM–midnight, +500), SUNDAY RESET (all Sunday, +500; the ISO week starts Monday, so Sunday is last call for the weekly bonus and for CREW WEEK). Seasons: S00 → S01 with a recap ceremony, frozen `SeasonRecord`s, permanent cosmetics. Live mechanics: `LiveOps` rules editable in `docs/live.json`: PR WEEKEND and CONTINUE? close S00; NIGHT SHIFT (+250 after 8 PM, all season) and FINAL BOSS (Halloween weekend, ×2 PR) define S01; CONTINUE? is every season's last call. Generic arcade vocabulary only, no game named. Community: CREW (Game Center friends who lift) with a shared weekly stake. Identity: Game Center alias, Season Pass title/color/badge, "SINCE SEP 2026", season history. Open opportunities: named crews with sides (S01 candidate), gym-hosted events, letting players create events.


---

## Hard rules (each with its why)

- **Counts are real.** Every presence number is Game Center players who actually pinged a board. Never inflate, never simulate, never hide a zero: "Nobody's on right now. Be first." is the honest state.
- **New persisted fields are Optional.** `PlayerProgress`, `WorkoutRewardSummary`, `WorldSnapshot`, `LiveSessionParticipation` use synthesized `Decodable`. A non-optional addition blanks every existing player's file. Write `var x: T? = nil`. `ProgressionService.save()` stamps `schemaVersion`; do not remove that.
- **Time goes through `ScheduledEventService.now()`** in the product layer so `-RUXPEventClock` works. Seasons go through `SeasonCatalog.current` so `-RUXPSeason` works. Live Ops rules go through `LiveOpsCatalog.current`.
- **Views never import GameKit.** GameKit lives in `RUXP/GameCenter/` behind services and `-Providing` protocols exposed through EnvironmentKeys (`\.liveEvents`, `\.livePresence`, `\.liveRoom`). Single-closure hooks (`onSnapshotChanged`, `onAuthenticated`, `onPresenceSubmitted`) are assigned once in `RUXPApp.init`; chain there, never elsewhere.
- **`Shared/` compiles into both targets.** Foundation only: no UIKit, GameKit, or SwiftUI-only types there.
- **Style: ChatGPT with hints of gaming.** Neutral near-black, system type, white pill buttons, hairline borders, no glows. The game shows in small doses: Orbitron wordmark, one hero number per screen, JetBrains Mono green for XP, magenta bar, red LIVE dot, one mono clock line. Use `Theme.*` tokens only. New scrolling screens without a nav bar get `.statusBarBackdrop()`. When in doubt, quieter.
- **Copy: short, honest, no manufactured urgency.** Uppercase eyebrows, sentence-case body, no exclamation marks. Zeros are shown as zeros.
- **Several Claude sessions may edit this tree at once.** Re-read a file right before editing, keep edits surgical, never full-file Write on a view.
- **Secrets never touch the repo or the chat.** The OpenAI key lives in gitignored `Config/Secrets.xcconfig`; `.githooks/pre-commit` blocks `sk-` literals. The user creates and pastes keys themselves.
- **Every season needs its Game Center boards before it starts:** `season_xp_sNN` and `season_goal_sNN` in App Store Connect (`Scripts/gamecenter_setup.py --all-seasons`), plus a Season Pass ladder in `SeasonPassCatalog`.
- **Live Ops rules change how XP is earned for a window; they never gate core function** and are capped by `LiveOpsCalendar.validationErrors()`.
- **Crew shows who is in, never who is out.** No shame lists, no crew streaks, no nudges. A quiet friend drops out of the crew silently after two weeks and rejoins by training. Accountability is positive presence ("MARCUS is lifting right now") and a shared stake (CREW WEEK), never guilt.
- **Commit and push only when asked.** The GitHub remote is `realworldbuilder/ruxp` (public; `docs/` is the live Pages site). Don't add feature detail to the public site without asking; it is an ARG-style teaser on purpose.

---

## Architecture map

```
Shared/                         both targets, Foundation only
  Models.swift, WorkoutStore.swift, HealthKitService.swift, ConnectivityConstants.swift
  RUXP/
    ProgressionModels.swift     PlayerProgress, XPAward, WorkoutRewardSummary, SeasonRecord
    ProgressionService.swift    XP rules, streaks, season rollover + recap, Live Ops awards
    LevelCurve.swift            level 1–100 from season XP (1000 + 150·(L−1) per level)
    Season.swift                SeasonCatalog (S00, S01), -RUXPSeason override
    LiveEvents.swift            LiveEvent, LiveEventProviding, ScheduledEventService (rituals)
    LiveOps.swift               LiveRule, LiveModifier, LiveOpsCalendar, LiveOpsCatalog (bundled + current)
    LivePresence.swift          LiveSnapshot, LivePresenceProviding
    GameCenterCatalog.swift     leaderboard/achievement IDs, App Store Connect window config
RUXP/                           iOS
  RUXPApp.swift                 builds the service graph, debug launch args, scenePhase
  WorkoutManager.swift          start/end, awards completion XP (+ Live Ops), presence pings
  AIProcessingPipeline.swift    voice notes → structured log → PRs → PR XP
  GameCenter/                   GameCenterService (auth, scores, friends, standing), GameCenterLivePresence, LiveRoomService
  Live/                         LiveSessionService (participations), LiveRoom protocol
  LiveOps/LiveOpsService.swift  cached remote docs/live.json, validation, -RUXPLiveOps
  World/                        WorldSnapshot + ReturnLedger (pure diff), WorldSnapshotService
  Crew/                         CrewModels (CrewMember, CrewSnapshot, CrewState), CrewService (friends who lift, CREW WEEK)
  SeasonPass/SeasonPassCatalog  per-season ladders, permanence, loadout
  Views/                        MainTabView (workout cover + season recap cover), HomeView (lobby), TrainView,
                                ProfileView, ActiveWorkoutTab, WorkoutCompletionSheet, SeasonRecapView,
                                SeasonPassView, LiveSessionView, LiveRoomPanel, LiveHistoryView, SettingsView,
                                Theme.swift, Components/ (RUXPComponents, ReturnLedgerCard)
RUXP Watch App/                 training only: WatchWorkoutManager, WatchGameCenter, Views/
docs/                           GitHub Pages site (index/privacy/support, config.js, live.json), ARCHITECTURE.md, PHILOSOPHY.md, APP-STORE-SUBMISSION.md
docs/kb/                        Knowledge base site (static HTML + kb.css/kb.js, screenshots in img/); not linked from the signal page

Scripts/                        ship.sh (archive + upload), asc.py, gamecenter_setup.py
```

A backend would replace, one protocol at a time: `LiveEventProviding` (gym/brand events), `LivePresenceProviding` (counts), `LiveOpsCatalog.current` (rules), `LiveRoomProviding` (rooms). None of that is speculatively wired.

---

## Build, run, verify

There is **no test target**. Verification is: build both schemes, run with DEBUG launch args, screenshot the simulator, inspect the JSON files.

```bash
xcodebuild -scheme RUXP -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme "RUXP Watch App" -destination 'generic/platform=watchOS Simulator' build
```

Xcode 16 synchronized folders: a new `.swift` file under `Shared/`, `RUXP/`, or `RUXP Watch App/` needs no pbxproj edit. Build without `CODE_SIGNING_ALLOWED=NO` when HealthKit matters (entitlements).

**DEBUG launch arguments** (`RUXPApp.applyDebugLaunchArguments`, all mirrored in Settings › Developer):

| Argument | Effect |
|---|---|
| `-RUXPSkipMinimum` | no 10-minute minimum for completion XP |
| `-RUXPSkipHealthKit` | bypass HealthKit (simulators) |
| `-RUXPSkipGameCenter` | no sign-in, scores, or live counts |
| `-RUXPLoadSamples` | seed 7 sample workouts on an empty install |
| `-RUXPEventClock friday\|sunday\|tuesday` | freeze the event clock at that day (frozen instant; countdowns don't tick) |
| `-RUXPTab train\|profile` | open on that tab (tab-bar taps are unreliable when driving the simulator) |
| `-RUXPLiveScene lobby\|active\|complete` | open the Live lobby, a joined workout, or the reward screen |
| `-RUXPSeason S00\|S01\|S02` | pretend that season is current (rollover + recap + ladders + boards) |
| `-RUXPLastSeen 3d\|18h\|45m` | pretend the last visit was that long ago (return ledger) |
| `-RUXPWorldDemo` | with Game Center off, seed friends/rank so every ledger line renders |
| `-RUXPLiveOps off\|<path.json>` | no rules, or a local calendar instead of the remote one |
| `-RUXPScreen seasonpass\|settings\|livehistory\|archivedpass` | open that sheet at launch (pair `settings`/`livehistory`/`archivedpass` with `-RUXPTab profile`) |
| `-RUXPCrewDemo room\|last\|final\|complete\|empty` | with Game Center off, seed a crew in that state (`final` + `-RUXPLiveScene complete` shows the CREW WEEK row) |


Typical: `-RUXPSkipGameCenter -RUXPSkipHealthKit -RUXPLoadSamples -RUXPSkipMinimum -RUXPLiveScene complete`.

**Driving the simulator from Bash.** The shell is zsh: build args as an array (`ARGS=(...)`, `"${ARGS[@]}"`) or `simctl launch` receives one argument. Use the device UDID with `simctl` (`booted` may pick the watch). `xcrun simctl io <UDID> screenshot out.png` works headless. `xcrun simctl get_app_container <UDID> com.whussey.ruxp data` finds `Documents/`. The iOS Simulator MCP needs `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (user's password). On-screen taps via `cliclick` work only while the display is unlocked and the Simulator window is visible to accessibility; prefer launch args over taps.

**Ship:** `Scripts/ship.sh` (needs `Config/Secrets.xcconfig`, Xcode signed into the Apple ID, ~20 GB free: check `df -h /System/Volumes/Data`). Bump `CURRENT_PROJECT_VERSION` in all four places in `RUXP.xcodeproj/project.pbxproj` first. Run archive/export with the Bash sandbox disabled so signing can reach the keychain.

**Site preview:** `.claude/launch.json` → `ruxp-site` (python http.server on 8765 serving `docs/`); the knowledge base is at `/kb/`. When a screen changes, recapture its screenshot into `docs/kb/img/` (`simctl io <UDID> screenshot`, then `sips -Z 900`) and update `docs/kb/screens.html`.


---

## Persistence

| Where | What |
|---|---|
| `Documents/workouts/index.json`, `workouts/<id>/session.json`, `workouts/<id>/audio/*.wav` | workouts and voice notes |
| `Documents/player_progress.json` | `PlayerProgress` (XP, streaks, ledgers, cosmetics, season history, schemaVersion) |
| `Documents/live_sessions.json` | Live Session participations |
| `Documents/world_snapshot.json` | last-seen world state for the return ledger |
| `Documents/live_ops.json` | cached remote Live Ops calendar |
| `Documents/insights_store.json`, `planned_workout.json`, `pending_ai_queue.json` | stats/PRs, trainer plan, offline parse queue |
| UserDefaults | `weightUnit`, `gameCenterSyncEnabled`, `gameCenter.cache`, `com.whussey.ruxp.activeWorkoutID`, `world.dismissedLedgerAt`, `ruxp.debugSeasonOverride`, `trainer_soul`, watch caches |

---

## Live Ops runbook

1. Edit `docs/live.json`. Dates are local wall-clock `yyyy-MM-dd'T'HH:mm` (a rule starts at each player's own midnight, like FRIDAY NIGHT). Rules: `{"type":"multiplier","reason":"personalRecord","factor":2}`, `{"type":"flatBonus","amount":250}`, `{"type":"startedBefore","hour":8,"amount":250}`, `{"type":"startedAfter","hour":20,"amount":250}`. A build that predates a rule type rejects the whole file and keeps its cached calendar.
2. Bump `version` (must be ≥ the bundled version in `LiveOpsCatalog.bundled`).
3. Keep within caps or the file is rejected wholesale: ≤ 32 rules, window ≤ 14 days (time-of-day rules `startedBefore`/`startedAfter` may run a season, ≤ 92 days), factor 1…3, bonus 0…1000, unique ids.
4. Push. Pages serves it; the app fetches at most once an hour on foreground. Settings › Developer shows the source and "Bundled round trip" checks the wire format.
5. Mirror durable entries into `LiveOpsCatalog.bundled` at the next build so offline players see them too.
6. A rule that needs a participant count needs a Game Center recurring board (see `GameCenterCatalog` header). Rules are client-side XP only; achievements and season goals are unaffected.

---

## Watching (not wired, check each Apple beta cycle)

**Richer strength sets in Apple Health.** The iOS 27 / watchOS 27 betas added a private per-set model to the health database: a strength `HKWorkoutActivity` per exercise (exercise type, muscle groups) holding sets with rep count, weight, equipment, body side, duration, repetition type. Found by code-diving the HealthDaemon framework (MacRumors forums, Sep 2026; diffs in `blacktop/ipsw-diffs`). As of iOS 27 beta 8 it is stubbed: no public header, no third-party write, nothing readable. This Mac has the iOS 26.2 SDK only. RUXP still writes one `traditionalStrengthTraining` workout per session and keeps sets in `session.json`.

- **Already done (Sep 2026):** `ExerciseSet` carries optional `side`, `equipment`, `momentIndex` (the voice moment a set was spoken in, which is how a set gets a timestamp later). The parser fills them only when spoken. Mapping when the door opens: one `ExerciseGroup` → one strength activity, one `ExerciseSet` → one set.
- **Trigger 1, write:** a public strength initializer on `HKWorkoutActivity` (or an `HKWorkoutSet`-style type) in a shipping SDK. Then attach sets from `HealthKitService` after the parse lands, remembering the workout is already closed by then and the watch may own it (`watchHealthWorkoutIDs`).
- **Trigger 2, read:** Apple's Workout app logging sets natively on Series 12 / Ultra 4. Then ingest them and award PR XP for lifts logged without voice. That is the aliveness win: more lifting becomes visible without changing how anyone trains.
- **Until then:** no `#available(iOS 27)` seam, no private selectors, no Xcode beta on the shipping machine. Detail in `docs/ARCHITECTURE.md` under "Later".

## Known debt (don't rediscover it)

- ~2,400 lines of unreachable Momentary code compile with no entry point: `ChatView`, `ChatBlockView`, `InsightsTab`, `InsightStoryView`, `StoryCarouselView`, `HomeIntelligenceEngine`, `InsightsIntelligenceEngine`, `StoryReadTracker`. `ChatEngine`/`ConversationStore` are constructed with no consumer. `InsightsEngine.generateInsights()` is intentionally not called (it spent the bundled key). Delete as a separate task.
- `InsightsStore.ingestedWorkoutIDs` is in-memory only; `prRewardsByWorkout` on `PlayerProgress` is the persisted backstop for XP.
- `ProgressionService.rebuild(from:)` credits all historical XP to the current season (only `seasonWorkoutCount` is season-gated); it matters more once S01 exists.
- Profile's PR tile is `max(prCount, personalRecords.count)`; `live_sessions` board submits `eventsJoined.count` while Profile shows `LiveSessionService.completedCount`.
- Season Pass tier 20 ≈ 44,650 XP ≈ both rituals every week all season. Intentional: the pass is finished by showing up, not grinding.
- Training Room needs two devices and two Apple IDs; untested in the simulator. Friend/rank ledger lines need a real device with Game Center friends.
