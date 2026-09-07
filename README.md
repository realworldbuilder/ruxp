<p align="center">
  <img src="RUXP/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="RUXP">
</p>

<h1 align="center">RUXP</h1>

<p align="center">
  <strong>The place you open when you're about to lift.</strong>
</p>

<p align="center">
  <a href="https://realworldbuilder.github.io/ruxp/"><strong>Season 0 · Early Adopters</strong></a> — join the TestFlight, AI voice logging on the house.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS_18+_|_watchOS_11+-black?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-FF2DAA?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License">
</p>

---

You might be alone at the gym on a Friday night, but you are not lifting alone. RUXP is a social, live-feeling weightlifting app for iPhone and Apple Watch. It makes the gym feel like something is happening right now.

## The loop

```
OPEN → SEE WHAT'S HAPPENING → START WORKOUT → EARN XP → SEE OTHER PEOPLE TRAINING → FINISH → COME BACK
```

That is the whole MVP. Everything in the app exists to serve it.

## What you see

**Home** answers four questions in one glance: who is training right now, is anything special happening, what level am I, should I start lifting.

```
RUXP                              S00 · EARLY ADOPTERS
12,481 ● LIFTING NOW
482 workouts finished in the last hour

● LIVE NOW                                   +500 XP
FRIDAY NIGHT
4,208 players joined
Train tonight. Earn bonus XP.
[ JOIN + START WORKOUT ]

YOU   LVL 12   3,420 / 4,000 XP
THIS WEEK  3 workouts   One more for your weekly bonus.
```

**Workout** is the Momentary engine: a real HealthKit strength session, voice notes transcribed on the fly, "8,903 still lifting" while you train, and the active event if one is live.

**Complete** is the moment that matters:

```
WORKOUT COMPLETE
  WORKOUT COMPLETE     +500 XP
  FRIDAY NIGHT         +500 XP
  NEW PR               +250 XP
+1,250 XP   LVL 12 → LVL 13
12,914 people trained tonight.
[ CONTINUE ]
```

**Train** is your history. **Profile** is your player card: level, lifetime XP, workouts, week streak, PRs, season, join date.

**Apple Watch** is for training, not browsing: lifting-now count, active event, Start Workout, timer, voice notes, End, then XP earned.

## XP

Users earn XP for healthy, useful behavior. Grinding is not rewarded.

| Action | XP | Rule |
|---|---|---|
| Complete a workout | +500 | 10+ minutes, max 2 rewarded per day |
| Join a live event | +500 | Workout overlaps the event window (FRIDAY NIGHT, SUNDAY RESET) |
| Live Ops rule | varies | A dated rule in effect (PR WEEKEND ×2 PR XP, EARLY SHIFT +250 before 8 AM, S00 FINALE +250). See `docs/live.json` |
| Weekly consistency | +500 | 4th workout of the ISO week |
| Personal record | +250 | Max 2 per workout, only after AI parses your notes |

Level 1–100 is derived from **season XP**; **lifetime XP** is a career total. Season 00 is EARLY ADOPTERS (Sep 1 – Nov 30, 2026): 32 workouts, finish the season. Season 01, PRESS START, starts Dec 1. `SeasonCatalog.current` picks the season active today. Everything lives in `ProgressionService`.

When a season closes, the first launch inside the next one shows a recap (final level, workouts, live sessions, Friday Nights, PRs, pass tier, the cosmetics you keep) and freezes it as a `SeasonRecord` on the profile. Season Pass cosmetics unlocked in a finished season stay equippable forever; Profile lists every season played.

## The world moves while you're gone

Home carries a one-line clock (`MON 10:42 AM · FRIDAY NIGHT IN 4D 6H · S00 ENDS IN 84D`) and, after an absence of six hours or more, a **WHILE YOU WERE GONE** card: which rituals ran (with the real join count if it was seen live), a friend who leveled up, your season-XP rank move, a new week for the weekly bonus, the season getting close to its end, new players on the season board. Every line is computed from the clock or observed from Game Center (`WorldSnapshotService`, `Documents/world_snapshot.json`); nothing is invented, and the card does not appear when nothing changed.

## Live Ops: rules, not features

`Shared/RUXP/LiveOps.swift` is a dated list of rules that change how XP is earned for a window: a multiplier on one reason, a flat bonus per workout, or a bonus for workouts started before an hour. The bundled copy ships in the app; `docs/live.json` on the site is fetched at most once an hour and replaces it when it validates (version, caps, window length). Edit the JSON, bump `version`, push: the rule is live on each player's next foreground. Rules show on the Home event card and the clock line and pay as an extra row on the reward screen.

## Live presence and events

Live counts are **real**. They come from Game Center, with no server of our own: an active workout pings a short recurring leaderboard every five minutes, and the number of players in that window is "lifting now". A daily board pinged on completion is "trained today"; weekly boards whose windows match the events are "players joined". `GameCenterLivePresence` polls those counts and sits behind `LivePresenceProviding`; the watch mirrors the phone's numbers (`MirroredLivePresence`) and pings on its own during a watch-run workout. Counts include only RUXP players signed into Game Center, so early on they are small and shown as they are. Events (FRIDAY NIGHT, SUNDAY RESET, the current season theme) come from `ScheduledEventService` behind `LiveEventProviding`.

## RUXP Live

You may be training alone, but you are not training alone. A timed event (SUNDAY RESET all day Sunday, FRIDAY NIGHT from 5 PM) is a lobby: JOIN SESSION on Home records a `LiveSessionParticipation` (keyed by the event occurrence and your Game Center player ID) and opens the session screen with the countdown, who you joined as, the real join count, your Game Center friends who play RUXP this season (with their level), an invite share sheet, and your history. Any strength workout finished while the event is live completes it: `ProgressionService` pays the event bonus once per occurrence, `LiveSessionService` records the completion against the workout, and the reward screen reads "Reset complete. You showed up." Starting a workout during an event joins it automatically, so nobody loses XP for skipping the lobby. History lives in Profile → Live sessions and in `Documents/live_sessions.json`.

The Training Room is an experiment: a 2–8 player Game Center real-time match (`LiveRoomService`, auto-matched by event occurrence) where the only messages are four reactions. Rooms are foreground-only (the peer connection drops when the phone locks), never retry on their own, and need two physical devices with two Apple IDs to test; the simulator cannot carry the peer transport. Members shown are always real Game Center players.

## Game Center

Sign-in is silent if the player is already in Game Center. Four leaderboards (lifetime XP, season XP, longest week streak, live sessions completed) and twelve achievements (first workout, first PR, four-workout week, four-week streak, Friday Night, first live session, five live sessions, season goal, levels 5/10/25/50) are submitted from `ProgressionService` totals, never deltas. Profile opens each leaderboard; Settings has an off switch. IDs and the App Store Connect window configuration are documented in `Shared/RUXP/GameCenterCatalog.swift`. A new season needs its own `season_xp_*` and `season_goal_*` entries created before it starts; Season 0 uses `season_xp_s00` and `season_goal_s00`.

## Architecture

```
RUXP/
├── RUXP.xcodeproj
├── Shared/                        (both targets)
│   ├── Models.swift               Workout, exercise/set/rep/weight, wire messages
│   ├── WorkoutStore.swift         Directory-per-workout JSON persistence
│   ├── HealthKitService.swift     HKWorkoutSession (watch) / manual HKWorkout (phone)
│   ├── ConnectivityConstants.swift
│   └── RUXP/
│       ├── LevelCurve.swift       Levels 1–100
│       ├── ProgressionModels.swift PlayerProgress, XPAward, WorkoutRewardSummary
│       ├── ProgressionService.swift Centralized XP / level / streak (player_progress.json)
│       ├── Season.swift           S00 EARLY ADOPTERS, S01 PRESS START
│       ├── LiveEvents.swift       LiveEvent, LiveEventProviding, ScheduledEventService
│       ├── LivePresence.swift     LiveSnapshot, LivePresenceProviding
│       ├── MirroredLivePresence.swift  Watch copy of the phone's counts
│       └── GameCenterCatalog.swift Leaderboard / achievement IDs, PlayerProgress → scores
├── RUXP/                          (iOS target)
│   ├── RUXPApp.swift
│   ├── GameCenter/
│   │   ├── GameCenterService.swift      Sign-in, XP + achievement submission, presence pings
│   │   └── GameCenterLivePresence.swift Polls recurring boards for real live counts
│   ├── WorkoutManager.swift       Start/end, awards completion XP, pushes reward to watch
│   ├── AIProcessingPipeline.swift OpenAI parse → structured log → PR detection → PR XP
│   ├── InsightsStore.swift        Lifetime stats, personal records
│   └── Views/
│       ├── MainTabView.swift      HOME / TRAIN / PROFILE + one workout cover
│       ├── HomeView.swift         The lobby
│       ├── TrainView.swift        History
│       ├── ProfileView.swift      Player card
│       ├── ActiveWorkoutTab.swift Live workout
│       ├── WorkoutCompletionSheet.swift  Reward screen
│       └── Components/RUXPComponents.swift
└── RUXP Watch App/                (watchOS target)
    ├── WatchWorkoutManager.swift  Workout lifecycle, receives XP from phone
    └── Views/                     WatchHomeView, ActiveWorkoutView, WorkoutSummaryView
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the protocols and what a real backend replaces, [docs/PHILOSOPHY.md](docs/PHILOSOPHY.md) for the living-product design philosophy, and [CLAUDE.md](CLAUDE.md) for the rules every change follows.


## Quick start

```bash
open RUXP.xcodeproj
```

Schemes: `RUXP` (iPhone) and `RUXP Watch App`. Bundle IDs `com.whussey.ruxp` and `com.whussey.ruxp.watchkitapp`.

### Requirements
- Xcode 16+ (built with 26.3)
- iOS 18.0+ / watchOS 11.0+

### Setup
1. Select your signing team.
2. Build and run on your devices.
3. Optional: add an OpenAI API key in Profile › Settings. It powers transcription and parsing voice notes into sets, reps, weight, and PRs. XP for completing workouts never depends on it.

### Building with the bundled key (Season 0)
Season 0 ships a developer-provided OpenAI key so early adopters get AI features on the house. The key is read at build time from a gitignored file and never committed:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # then paste the key after RUXP_OPENAI_KEY =
git config core.hooksPath .githooks                           # refuses commits containing an sk- key
```

Without `Config/Secrets.xcconfig` the app builds in bring-your-own-key mode. A key pasted in Settings always overrides the bundled one. `Scripts/ship.sh` refuses to archive without the file and verifies the key landed in the archive.

### Debug helpers
Debug builds add a Developer section in Settings (load 7 sample workouts, pretend it is Friday night, skip the 10-minute minimum, season override, Game Center state and presence counts, live ops source, world snapshot) and accept launch arguments `-RUXPSkipMinimum`, `-RUXPEventClock friday|sunday|tuesday`, `-RUXPSkipHealthKit`, `-RUXPSkipGameCenter`, `-RUXPLiveScene lobby|active|complete`, `-RUXPSeason S00|S01`, `-RUXPLastSeen 3d|18h|45m`, `-RUXPWorldDemo`, and `-RUXPLiveOps off|<path.json>`.


## Privacy

Voice notes are sent to OpenAI for transcription and parsing. During Season 0 the app ships a developer-provided key; you can replace it with your own in Settings. No analytics, no tracking, no accounts of our own. Game Center is optional and can be turned off in Settings; when on, only your XP totals, week streak, milestones, and an "I'm training" ping leave the device, and the live counts are read back from it.

## License

[MIT](LICENSE)
