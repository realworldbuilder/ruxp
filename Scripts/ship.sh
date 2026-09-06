#!/bin/bash
# RUXP Ship Script — archives and uploads to TestFlight.
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
PROJECT_DIR="$REPO_ROOT"
SCHEME="RUXP"
ARCHIVE_PATH="/tmp/ruxp.xcarchive"
EXPORT_PATH="/tmp/ruxp-export"
EXPORT_PLIST="$REPO_ROOT/ExportOptions.plist"
SECRETS="$REPO_ROOT/Config/Secrets.xcconfig"

# Preflight: the bundled OpenAI key must exist locally and must not be tracked.
[ -f "$SECRETS" ] || { echo "❌ $SECRETS missing. Copy Config/Secrets.example.xcconfig and add the key."; exit 1; }
KEY_VALUE="$(grep -E '^[[:space:]]*RUXP_OPENAI_KEY[[:space:]]*=' "$SECRETS" | tail -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
[ -n "$KEY_VALUE" ] || { echo "❌ RUXP_OPENAI_KEY is empty in Config/Secrets.xcconfig."; exit 1; }
if git -C "$REPO_ROOT" ls-files --error-unmatch Config/Secrets.xcconfig >/dev/null 2>&1; then
  echo "❌ Config/Secrets.xcconfig is tracked by git. Untrack it before shipping."; exit 1
fi
echo "🔑 Bundled OpenAI key: Config/Secrets.xcconfig (…${KEY_VALUE: -4})"

rm -rf "$EXPORT_PATH"

echo "📦 Step 1: Archiving..."
cd "$PROJECT_DIR"
/usr/bin/xcodebuild -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive -allowProvisioningUpdates \
  2>&1 | grep -E "ARCHIVE (SUCCEEDED|FAILED)|error:"

BUILT_KEY="$(/usr/libexec/PlistBuddy -c 'Print :RUXPOpenAIKey' "$ARCHIVE_PATH/Products/Applications/RUXP.app/Info.plist" 2>/dev/null || true)"
if [ -z "$BUILT_KEY" ] || [ "$BUILT_KEY" = '$(RUXP_OPENAI_KEY)' ]; then
  echo "❌ Archive has no bundled key (RUXPOpenAIKey empty). Check Config/RUXP.xcconfig is the base configuration."; exit 1
fi
echo "🔑 Archive carries the bundled key (…${BUILT_KEY: -4})"

echo "🚀 Step 2: Exporting + uploading to TestFlight..."
/usr/bin/xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  2>&1 | grep -E "EXPORT (SUCCEEDED|FAILED)|error:|Uploaded package"

echo "✅ Done!"
