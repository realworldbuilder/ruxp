#!/bin/bash
# M2M Ship Script — archives and uploads to TestFlight.
# ExportOptions.plist at the repo root has destination=upload, so the export
# step uploads straight to App Store Connect — no separate altool step.
#
# Signing/upload auth uses the Apple ID signed into Xcode (cloud-managed
# distribution certificate). The ASC API keys in ~/private_keys currently
# lack the "Access to Cloud Managed Distribution Certificate" permission,
# so passing -authenticationKey* flags fails with a cloud signing
# permission error — grant that permission in App Store Connect
# (Users and Access → Integrations) before switching to key-based auth.

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/Momentary"
SCHEME="Mind2Muscle"
ARCHIVE_PATH="/tmp/m2m.xcarchive"
EXPORT_PATH="/tmp/m2m-export"
EXPORT_PLIST="$REPO_ROOT/ExportOptions.plist"

rm -rf "$EXPORT_PATH"

echo "📦 Step 1: Archiving..."
cd "$PROJECT_DIR"
/usr/bin/xcodebuild -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive -allowProvisioningUpdates \
  2>&1 | grep -E "ARCHIVE (SUCCEEDED|FAILED)|error:"

echo "🚀 Step 2: Exporting + uploading to TestFlight..."
/usr/bin/xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  2>&1 | grep -E "EXPORT (SUCCEEDED|FAILED)|error:|Uploaded package"

echo "✅ Done!"
