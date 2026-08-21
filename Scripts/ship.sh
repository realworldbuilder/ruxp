#!/bin/bash
# M2M Ship Script — archives and uploads to TestFlight.
# ExportOptions.plist at the repo root has destination=upload, so the export
# step uploads straight to App Store Connect — no separate altool step.
# Auth uses an ASC API key at ~/private_keys/AuthKey_<API_KEY_ID>.p8.
# Override with: API_KEY_ID=XXXX API_ISSUER_ID=YYYY Scripts/ship.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/Momentary"
SCHEME="Mind2Muscle"
ARCHIVE_PATH="/tmp/m2m.xcarchive"
EXPORT_PATH="/tmp/m2m-export"
EXPORT_PLIST="$REPO_ROOT/ExportOptions.plist"
API_KEY_ID="${API_KEY_ID:-A2TTG7BZXD}"
API_ISSUER_ID="${API_ISSUER_ID:-69a6de75-5739-47e3-e053-5b8c7c11a4d1}"
API_KEY_FILE="$HOME/private_keys/AuthKey_${API_KEY_ID}.p8"

rm -rf "$EXPORT_PATH"

echo "📦 Step 1: Archiving..."
cd "$PROJECT_DIR"
/usr/bin/xcodebuild -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_FILE" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  2>&1 | grep -E "ARCHIVE (SUCCEEDED|FAILED)|error:"

echo "🚀 Step 2: Exporting + uploading to TestFlight..."
/usr/bin/xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_FILE" \
  -authenticationKeyID "$API_KEY_ID" \
  -authenticationKeyIssuerID "$API_ISSUER_ID" \
  2>&1 | grep -E "EXPORT (SUCCEEDED|FAILED)|error:|Upload"

echo "✅ Done!"
