#!/bin/bash
# M2M Ship Script — archives, exports, and uploads to TestFlight
# Uses ASC API key for upload — no interactive Apple ID login needed

set -e

PROJECT_DIR="/Users/williamhussey/.openclaw/workspace/repos/momentary/Momentary"
SCHEME="Mind2Muscle"
ARCHIVE_PATH="/tmp/m2m.xcarchive"
EXPORT_PATH="/tmp/m2m-export"
EXPORT_PLIST="/tmp/export-options-manual.plist"
API_KEY_PATH="$HOME/.openclaw/keys/AuthKey_BMNYF2B89H.p8"
API_KEY_ID="BMNYF2B89H"
API_ISSUER_ID="69a6de75-5739-47e3-e053-5b8c7c11a4d1"

# Clean previous export
rm -rf "$EXPORT_PATH"

echo "📦 Step 1: Archiving..."
cd "$PROJECT_DIR"
/usr/bin/xcodebuild -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive -allowProvisioningUpdates \
  2>&1 | grep -E "ARCHIVE (SUCCEEDED|FAILED)|error:"

echo "📤 Step 2: Exporting IPA..."
/usr/bin/xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  2>&1 | grep -E "EXPORT (SUCCEEDED|FAILED)|error:"

IPA=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)
if [ -z "$IPA" ]; then
  echo "❌ No IPA found after export"
  exit 1
fi

echo "🚀 Step 3: Uploading to TestFlight..."
/usr/bin/xcrun altool --upload-app \
  -f "$IPA" \
  -t ios \
  --apiKey "$API_KEY_ID" \
  --apiIssuer "$API_ISSUER_ID" \
  2>&1

echo "✅ Done!"
