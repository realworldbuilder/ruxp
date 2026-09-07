#!/usr/bin/env python3
"""Tiny App Store Connect API client. Usage: asc.py GET /v1/apps?filter[bundleId]=... | asc.py POST /v1/x '{json}'"""
import json, os, sys, time, urllib.request, urllib.error
import jwt
env = {}
for line in open(os.path.expanduser("~/.wristassist_env")):
    line = line.strip()
    if line.startswith("export "):
        k, v = line[7:].split("=", 1); env[k] = v.strip().strip('"').strip("'")
KEY_ID, ISSUER = env["APPSTORE_KEY_ID"], env["APPSTORE_ISSUER_ID"]
key = open(os.path.expanduser(f"~/private_keys/AuthKey_{KEY_ID}.p8")).read()
def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}, key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(method, path, body=None):
    url = path if path.startswith("http") else "https://api.appstoreconnect.apple.com" + path
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try: return e.code, json.loads(raw)
        except Exception: return e.code, {"raw": raw.decode(errors="replace")}
if __name__ == "__main__":
    m, p = sys.argv[1], sys.argv[2]
    b = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    st, out = call(m, p, b); print(st); print(json.dumps(out, indent=1)[:6000])
