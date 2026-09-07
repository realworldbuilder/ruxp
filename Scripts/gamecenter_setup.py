#!/usr/bin/env python3
"""Idempotent Game Center setup for RUXP via the App Store Connect API.

Creates (if missing) every leaderboard and achievement in Shared/RUXP/GameCenterCatalog.swift,
each with an en-US localization. Safe to re-run; add a season and run again before it starts.

Needs ~/.wristassist_env (APPSTORE_KEY_ID, APPSTORE_ISSUER_ID) and ~/private_keys/AuthKey_<id>.p8
with App Manager or Admin access. Recurring boards must start in the future, so their first
occurrence is placed on the next grid boundary; the rule keeps them aligned afterwards.
"""
import datetime as dt, json, sys
from asc import call

BUNDLE_ID = "com.whussey.ruxp"
SEASONS = ["s00", "s01"]          # add the next season here before Dec 1
SEASON_NAMES = {"s00": "Season 0", "s01": "Season 1"}
SEASON_GOALS = {"s00": 32, "s01": 32}
ET = dt.timezone(dt.timedelta(hours=-4))

def app_id():
    st, out = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    return out["data"][0]["id"]

def detail_id(app):
    st, out = call("GET", f"/v1/apps/{app}/gameCenterDetail")
    if out.get("data"): return out["data"]["id"]
    st, out = call("POST", "/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails", "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})
    assert st == 201, out
    return out["data"]["id"]

def recurring_starts():
    now = dt.datetime.now(ET) + dt.timedelta(minutes=3)
    def grid(offset):
        base = now.replace(second=0, microsecond=0)
        for c in (offset, offset + 30):
            if c > base.minute: return base.replace(minute=c)
        return (base + dt.timedelta(hours=1)).replace(minute=offset)
    def weekday(wd, hour):
        d = now.replace(hour=hour, minute=0, second=0, microsecond=0)
        while d.weekday() != wd or d <= now: d += dt.timedelta(days=1)
        return d
    midnight = (now + dt.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    iso = lambda d: d.isoformat(timespec="seconds")
    return {
        "active_a": (iso(grid(0)), "PT30M", "FREQ=MINUTELY;INTERVAL=30"),
        "active_b": (iso(grid(15)), "PT30M", "FREQ=MINUTELY;INTERVAL=30"),
        "trained_today": (iso(midnight), "PT24H", "FREQ=DAILY;INTERVAL=1"),
        "event_friday_night": (iso(weekday(4, 12)), "PT18H", "FREQ=DAILY;INTERVAL=7"),
        "event_sunday_reset": (iso(weekday(6, 0)), "PT30H", "FREQ=DAILY;INTERVAL=7"),
        "crew_week": (iso(weekday(0, 0)), "PT168H", "FREQ=DAILY;INTERVAL=7"),
    }

def leaderboards():
    boards = [("lifetime_xp", "Lifetime XP"), ("week_streak", "Longest Week Streak"), ("live_sessions", "Live Sessions")]
    boards += [(f"season_xp_{s}", f"{SEASON_NAMES[s]} XP") for s in SEASONS]
    rec = recurring_starts()
    boards += [("active_a", "Lifting now A"), ("active_b", "Lifting now B"), ("trained_today", "Trained today"), ("event_friday_night", "Friday Night"), ("event_sunday_reset", "Sunday Reset"), ("crew_week", "Crew week")]

    return [(vid, name, rec.get(vid)) for vid, name in boards]

def achievements():
    a = [
        ("first_workout", "First Workout", 5, "Finish your first workout.", "You finished your first workout."),
        ("first_pr", "First PR", 5, "Log your first personal record.", "You logged your first personal record."),
        ("four_workout_week", "Four in a Week", 10, "Finish four workouts in one week.", "Four workouts in one week."),
        ("four_week_streak", "Four-Week Streak", 15, "Keep a four-week streak.", "Four weeks straight."),
        ("friday_night", "Friday Night", 10, "Train during Friday Night.", "You trained on Friday Night."),
        ("live_first_session", "Sunday Reset", 10, "Complete your first RUXP Live Session.", "You completed your first Live Session."),
        ("live_five_sessions", "Showed Up", 15, "Complete 5 Live Sessions.", "Five Live Sessions. You showed up."),
        ("level_5", "Level 5", 5, "Reach level 5.", "Level 5."),
        ("level_10", "Level 10", 5, "Reach level 10.", "Level 10."),
        ("level_25", "Level 25", 10, "Reach level 25.", "Level 25."),
        ("level_50", "Level 50", 15, "Reach level 50.", "Level 50."),
    ]
    for s in SEASONS:
        a.append((f"season_goal_{s}", f"{SEASON_NAMES[s]} Complete", 20, f"Finish {SEASON_GOALS[s]} workouts in {SEASON_NAMES[s]}.", f"{SEASON_NAMES[s]} complete."))
    return a

def main():
    only_current = "--all-seasons" not in sys.argv
    app = app_id(); detail = detail_id(app)
    print("app", app, "gameCenterDetail", detail)
    st, out = call("GET", f"/v1/gameCenterDetails/{detail}/gameCenterLeaderboards?limit=200")
    have = {d["attributes"]["vendorIdentifier"] for d in out.get("data", [])}
    for vid, name, rec in leaderboards():
        if only_current and vid.startswith("season_xp_") and not vid.endswith(SEASONS[0]): continue
        if vid in have: print("exists ", vid); continue
        attrs = {"defaultFormatter": "INTEGER", "referenceName": name, "vendorIdentifier": vid, "submissionType": "BEST_SCORE", "scoreSortType": "DESC"}
        if rec: attrs.update({"recurrenceStartDate": rec[0], "recurrenceDuration": rec[1], "recurrenceRule": rec[2]})
        st, out = call("POST", "/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards", "attributes": attrs, "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail}}}}})
        if st != 201: print("FAILED ", vid, st, json.dumps(out.get("errors", out))[:400]); continue
        lid = out["data"]["id"]
        call("POST", "/v1/gameCenterLeaderboardLocalizations", {"data": {"type": "gameCenterLeaderboardLocalizations", "attributes": {"locale": "en-US", "name": name}, "relationships": {"gameCenterLeaderboard": {"data": {"type": "gameCenterLeaderboards", "id": lid}}}}})
        print("created", vid, rec[0] if rec else "")
    st, out = call("GET", f"/v1/gameCenterDetails/{detail}/gameCenterAchievements?limit=200")
    have = {d["attributes"]["vendorIdentifier"] for d in out.get("data", [])}
    for vid, name, pts, before, after in achievements():
        if only_current and vid.startswith("season_goal_") and not vid.endswith(SEASONS[0]): continue
        if vid in have: print("exists ", vid); continue
        st, out = call("POST", "/v1/gameCenterAchievements", {"data": {"type": "gameCenterAchievements", "attributes": {"referenceName": name, "vendorIdentifier": vid, "points": pts, "showBeforeEarned": True, "repeatable": False}, "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail}}}}})
        if st != 201: print("FAILED ", vid, st, json.dumps(out.get("errors", out))[:400]); continue
        aid = out["data"]["id"]
        call("POST", "/v1/gameCenterAchievementLocalizations", {"data": {"type": "gameCenterAchievementLocalizations", "attributes": {"locale": "en-US", "name": name, "beforeEarnedDescription": before, "afterEarnedDescription": after}, "relationships": {"gameCenterAchievement": {"data": {"type": "gameCenterAchievements", "id": aid}}}}})
        print("created", vid, pts, "pts")

if __name__ == "__main__":
    main()
