# RUXP — TestFlight and App Store submission guide (Season 0)

A checklist for 1.0 build 4. Work top to bottom. Items marked **you** need the Apple ID, the OpenAI account, or a real device, so they can't be automated from this repo.

Site: https://realworldbuilder.github.io/ruxp/ · Privacy: `/privacy.html` · Support: `/support.html`

---

## A. Before uploading build 4

1. **you** — Create the OpenAI key. At platform.openai.com create a *project* named `RUXP Season 0`, add a **monthly budget limit** to it (Settings › Limits), and create an API key inside that project restricted to `gpt-4o`, `gpt-4o-mini`, `whisper-1`. The key ships inside the app binary and can be extracted by anyone with the IPA, so the budget cap is the real safeguard. Then:
   ```bash
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig && open -e Config/Secrets.xcconfig
   ```
   paste the key after `RUXP_OPENAI_KEY = ` and save. Confirm `git status` does not list the file.
2. `git config core.hooksPath .githooks` once per clone. The hook refuses any commit containing an `sk-` key.
3. Disk: `df -h /System/Volumes/Data` should show 20 GB or more free (a Release build filled the disk once).
4. **you** — Xcode › Settings › Accounts must show your Apple ID. The export step fails with "Failed to Use Accounts" otherwise.
5. Ship:
   ```bash
   Scripts/ship.sh
   ```
   It refuses to archive without the secret, verifies the key landed in the archive, uploads, and prints "Uploaded package". Wait for App Store Connect to finish "Processing" (5–20 min).
6. Test the build on a real iPhone + Watch through internal TestFlight before anything below: start a workout, say one note, end it, confirm the transcript appears (proves the bundled key works over the network).

## B. App Store Connect — App Information (once)

| Field | Value |
|---|---|
| Name | RUXP |
| Subtitle | You're not lifting alone. |
| Primary category | Health & Fitness |
| Secondary category | Sports |
| Privacy Policy URL | https://realworldbuilder.github.io/ruxp/privacy.html |
| Support URL | https://realworldbuilder.github.io/ruxp/support.html |
| Marketing URL | leave blank (the home page is a dark teaser until launch) |
| Content rights | Does not contain third-party content |
| License agreement | Apple standard EULA |
| Age rating | Answer "None" to everything; result 4+. "Medical/Treatment Information": None. "Unrestricted Web Access": No. |

**Contact email for review and TestFlight feedback must be a mailbox that actually receives mail.** The public pages show admin@ruxp.app; if that domain is not receiving mail yet, use a real inbox in App Store Connect and keep admin@ruxp.app on the site only until forwarding exists.

## C. Game Center (blocking: live counts and leaderboards are dead without it)

**Done on 2026-09-07 via the App Store Connect API** (`Scripts/gamecenter_setup.py`, idempotent; re-run it after adding a season to `SEASONS`). Game Center is enabled on the app record and every ID below exists with an en-US name. Still **you**: achievements need a 512×512 image each before App Store release (not needed for TestFlight), and on the 1.0 version page › Game Center, attach the leaderboards and achievements to the version before submitting.

Reference: IDs and window settings are documented in `Shared/RUXP/GameCenterCatalog.swift`.

**Classic leaderboards** (score format: integer, sort high-to-low, submit best score)

| ID | Name |
|---|---|
| `lifetime_xp` | Lifetime XP |
| `season_xp_s00` | Season 0 XP |
| `week_streak` | Longest Week Streak |
| `live_sessions` | Live Sessions |

**Recurring leaderboards** (these are the presence counters; the score is a timestamp, sort high-to-low)

| ID | Name | Duration | Restart | Notes |
|---|---|---|---|---|
| `active_a` | Lifting now A | 30 min | every 30 min | start at :00 |
| `active_b` | Lifting now B | 30 min | every 30 min | start at :15 (staggered) |
| `trained_today` | Trained today | 24 h | daily | midnight UTC |
| `event_friday_night` | Friday Night | see catalog | weekly | padded to cover US time zones |
| `event_sunday_reset` | Sunday Reset | see catalog | weekly | padded to cover US time zones |

**Achievements** (100 points total across all; suggested split below)

| ID | Name | Points |
|---|---|---|
| `first_workout` | First workout | 5 |
| `first_pr` | First PR | 5 |
| `four_workout_week` | Four in a week | 10 |
| `four_week_streak` | Four-week streak | 15 |
| `friday_night` | Friday Night | 10 |
| `live_first_session` | Sunday Reset (first Live Session) | 10 |
| `live_five_sessions` | Showed Up (5 Live Sessions) | 15 |
| `season_goal_s00` | Season 0 complete | 20 |
| `level_5` | Level 5 | 5 |
| `level_10` | Level 10 | 5 |
| `level_25` | Level 25 | 10 |
| `level_50` | Level 50 | 15 |

Recurring boards can only start in the future, so the API placed each first occurrence on the next grid boundary (active windows within the hour, `trained_today` at the next midnight Eastern, events on the coming Friday/Sunday). `season_xp_s01`, `season_goal_s01`, `season_xp_s02`, `season_goal_s02` were added on 2026-09-07 with `python3 Scripts/gamecenter_setup.py --all-seasons`; the S00 goal text was patched to 12 workouts. Re-run the script after adding a season to `SEASONS`.

## D. App Privacy (nutrition label)

Matches `RUXP/PrivacyInfo.xcprivacy`.

- Data collection: **Yes**.
- **Audio Data** → App Functionality → Not linked to identity → Not used for tracking.
- **Fitness** (Health & Fitness › Fitness) → App Functionality → Not linked → Not used for tracking.
- Everything else (Contact Info, Identifiers, Usage Data, Diagnostics, Health): **not collected**. HealthKit data never leaves the device, so it is not "collected" in Apple's sense; the review notes say so explicitly.
- "Do you or your third-party partners use data for tracking purposes?" → **No**.

## E. Version 1.0 page

**Screenshots** (required sizes for 2026 submissions)

- iPhone 6.9" — 1320 × 2868 (iPhone 17 Pro Max simulator). Five shots, in this order: Home lobby, Season Pass, Active workout, Workout complete (+XP), Profile.
- Apple Watch — 416 × 496 (Series 10 46 mm). Three shots: Watch home, Active workout, Summary.
- iPad: not required (`TARGETED_DEVICE_FAMILY = 1`).

Capture from the simulator with sample data:
```bash
xcrun simctl launch <udid> com.whussey.ruxp -RUXPLoadSamples -RUXPSkipHealthKit -RUXPSkipGameCenter -RUXPEventClock friday
xcrun simctl io <udid> screenshot ~/Desktop/ruxp-1.png
```
Game Center counts show a dash in that mode; that is honest and acceptable. Do not add fake numbers.

**Text** — copy from `AppStoreText.md` (subtitle, promotional text, description, keywords, What's New).

**Build** — select build 4. Export compliance is pre-answered by `ITSAppUsesNonExemptEncryption = NO` (HTTPS only).

**App Review Information**

- Sign-in required: **No** (there are no accounts).
- Contact: a phone number and the live inbox from section B.
- Notes — paste this:

> RUXP is a weightlifting companion for iPhone and Apple Watch. No account or sign-in exists. Game Center is optional and can be turned off in Profile › Settings; when on, the "lifting now" and "trained today" numbers are real Game Center player counts and will be small or show "—" during review.
>
> Voice notes: during a workout the user can talk through their sets. The audio is sent to OpenAI (Whisper) for transcription and the transcript is sent to OpenAI (GPT-4o) to build a structured log. During Season 0 the app includes a developer-provided OpenAI key so this works without setup; users may substitute their own key in Settings. Nothing from HealthKit is ever sent to OpenAI: the app writes strength workouts to Apple Health and reads workouts to show history, and that data stays on device. See the privacy policy for the full list.
>
> To test in 60 seconds: tap START WORKOUT on Home, allow the microphone, hold the record button and say "bench press 135 for 8", tap END. The transcript appears on the Train tab within a few seconds. XP is awarded only for sessions of 10 minutes or more (a deliberate anti-grind rule), so a short test workout will show 0 XP; this is expected behavior.
>
> The Apple Watch app is optional and mirrors the phone: it needs Health permission on first launch to start a workout session.

**Sign in with Apple** is not required (guideline 4.8 applies only when third-party login exists; RUXP has none).

## F. TestFlight external testing (do this first; it's a lighter review)

1. TestFlight tab › External Testing › **+** group "Early Adopters".
2. Add build 4. Fill Beta App Review information: description (use the App Store description), feedback email (live inbox), privacy policy URL, "What to Test": *Start a workout, talk through a set, end it, check the XP screen and the Train tab. Open Profile › Season Pass. If you wear an Apple Watch, start a workout from the watch.*
3. Enable **Public link**, set a tester limit (500 is a sensible cap), copy the link.
4. Paste the link into `docs/config.js` as `TESTFLIGHT_URL` and commit. The site's buttons switch from "coming soon" to "Join the TestFlight" on their own.
5. Beta App Review usually clears within 48 hours. Builds expire after 90 days; each new build needs to be added to the group (later builds skip review unless the app changed materially).

## G. Rejection traps specific to this app, and the fix for each

| Trap | Guideline | Fix already in place / to do |
|---|---|---|
| Missing privacy manifest / required-reason API | ITMS-91053 | `PrivacyInfo.xcprivacy` in both targets declares UserDefaults CA92.1 |
| "App requires an external account or API key" | 2.1 / 5.1.1 | Bundled key for Season 0; notes state no key is required to test |
| Health data shared with third parties | 5.1.3 | Privacy page says HealthKit data never leaves the device; verified nothing HealthKit-derived is in the prompts |
| iPad screenshots demanded | — | Device family set to iPhone only |
| Game Center features "not working" | 2.1 | Create and attach every ID in section C before submitting |
| Watch app crashes on first launch | 2.1 | Test on a fresh device: the HealthKit prompt must be accepted before Start works |
| Placeholder links on the marketing/support site | 1.0 / 5.1.1 | Support and privacy pages are complete; TestFlight button says "coming soon" until the link exists |
| Mic permission string not explaining data use | 5.1.1 | Usage string names OpenAI and the purpose |

## H. After approval

1. Put the App Store link in `docs/config.js` as `APP_STORE_URL`; the site shows the App Store button automatically.
2. Tag the release: `git tag v1.0-s0 && git push origin v1.0-s0`.
3. Rotate the OpenAI key on Dec 1 with the Season 1 build (Season 1 should move AI calls behind a small proxy so the key no longer ships in the binary; `APIKeyProvider.keySource` is the seam).

## I. Each later build

- Bump `CURRENT_PROJECT_VERSION` in all four places in `RUXP.xcodeproj/project.pbxproj` (or `agvtool new-version -all N`).
- `Scripts/ship.sh`, then add the build to the Early Adopters group.
