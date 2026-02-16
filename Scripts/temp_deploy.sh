#!/bin/bash

# Momentary TestFlight Deployment Script
# Automates: Clean -> Build Number Increment -> Archive -> Export IPA -> Upload to TestFlight

set -e

# ========== Configuration ==========
PROJECT_NAME="Momentary"
SCHEME_NAME="Momentary"
BUNDLE_ID="com.whussey.momentary"
TEAM_ID="R2C4T4N7US"

# Resolve repo root (Scripts/ lives one level below)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$REPO_ROOT/Momentary/Momentary.xcodeproj"
PROJECT_DIR="$REPO_ROOT/Momentary"
EXPORT_OPTIONS_PLIST="$REPO_ROOT/ExportOptions.plist"

ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/${PROJECT_NAME}.xcarchive"
EXPORT_PATH="$HOME/Desktop/${PROJECT_NAME}-Export"
IPA_PATH="${EXPORT_PATH}/${PROJECT_NAME}.ipa"

# Load API credentials
if [ -f "$HOME/.momentary_env" ]; then
    source "$HOME/.momentary_env"
elif [ -f "$HOME/.wristassist_env" ]; then
    source "$HOME/.wristassist_env"
fi

API_KEY_ID="${APPSTORE_KEY_ID}"
API_ISSUER_ID="${APPSTORE_ISSUER_ID}"
API_KEY_PATH="$HOME/private_keys/AuthKey_${API_KEY_ID}.p8"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== Functions ==========

print_header() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}   Momentary TestFlight Deployment${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

check_prerequisites() {
    echo "Checking prerequisites..."

    # Check for Xcode
    if ! command -v xcodebuild &> /dev/null; then
        echo -e "${RED}Xcode command line tools not found${NC}"
        echo "Install with: xcode-select --install"
        SKIP_UPLOAD=true
    fi

    # Check for project
    if [ ! -f "$PROJECT_PATH/project.pbxproj" ]; then
        echo -e "${RED}Project not found at $PROJECT_PATH${NC}"
        echo "Run this script from the repo root or the Scripts/ directory"
        SKIP_UPLOAD=true
    fi

    # Check for ExportOptions.plist
    if [ ! -f "$EXPORT_OPTIONS_PLIST" ]; then
        echo -e "${RED}ExportOptions.plist not found at $EXPORT_OPTIONS_PLIST${NC}"
        SKIP_UPLOAD=true
    fi

    # Check for API credentials
    if [ -z "$API_KEY_ID" ] || [ -z "$API_ISSUER_ID" ]; then
        echo -e "${YELLOW}App Store Connect API credentials not configured${NC}"
        echo ""
        echo "To set up API access:"
        echo "  Run: ./Scripts/setup_testflight.sh"
        echo ""
        read -p "Continue without upload capability? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            SKIP_UPLOAD=true
        fi
        SKIP_UPLOAD=true
    fi

    echo -e "${GREEN}Prerequisites checked${NC}"
}

increment_build_number() {
    echo ""
    echo "Incrementing build number..."

    # agvtool has no -project flag; must run from the directory containing the xcodeproj
    CURRENT_BUILD=$(cd "$PROJECT_DIR" && xcrun agvtool what-version -terse | head -1)

    if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
        NEW_BUILD=$((CURRENT_BUILD + 1))
        (cd "$PROJECT_DIR" && xcrun agvtool new-version -all "$NEW_BUILD" >/dev/null)
        echo "  Current build: $CURRENT_BUILD"
        echo "  New build: $NEW_BUILD"
        echo -e "${GREEN}Build number updated to $NEW_BUILD${NC}"
    else
        echo -e "${YELLOW}Could not read numeric build number (got: '$CURRENT_BUILD'). Skipping auto-increment.${NC}"
        NEW_BUILD="unknown"
    fi
}

clean_build() {
    echo ""
    echo "Cleaning build folder..."

    if command -v xcpretty &> /dev/null; then
        xcodebuild clean \
            -project "$PROJECT_PATH" \
            -scheme "$SCHEME_NAME" \
            -configuration Release \
            | xcpretty
    else
        xcodebuild clean \
            -project "$PROJECT_PATH" \
            -scheme "$SCHEME_NAME" \
            -configuration Release \
            -quiet
    fi

    echo -e "${GREEN}Build folder cleaned${NC}"
}

build_archive() {
    echo ""
    echo "Building and archiving..."

    if command -v xcpretty &> /dev/null; then
        xcodebuild archive \
            -project "$PROJECT_PATH" \
            -scheme "$SCHEME_NAME" \
            -configuration Release \
            -archivePath "$ARCHIVE_PATH" \
            -destination "generic/platform=iOS" \
            -allowProvisioningUpdates \
            DEVELOPMENT_TEAM="$TEAM_ID" \
            | xcpretty
    else
        xcodebuild archive \
            -project "$PROJECT_PATH" \
            -scheme "$SCHEME_NAME" \
            -configuration Release \
            -archivePath "$ARCHIVE_PATH" \
            -destination "generic/platform=iOS" \
            -allowProvisioningUpdates \
            DEVELOPMENT_TEAM="$TEAM_ID"
    fi

    if [ ! -d "$ARCHIVE_PATH" ]; then
        echo -e "${RED}Archive failed${NC}"
        SKIP_UPLOAD=true
    fi

    echo -e "${GREEN}Archive created successfully${NC}"
}

export_ipa() {
    echo ""
    echo "Exporting IPA for App Store..."

    EXPORT_OK=false
    if command -v xcpretty &> /dev/null; then
        if xcodebuild -exportArchive \
            -archivePath "$ARCHIVE_PATH" \
            -exportPath "$EXPORT_PATH" \
            -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
            -allowProvisioningUpdates \
            | xcpretty; then
            EXPORT_OK=true
        fi
    else
        if xcodebuild -exportArchive \
            -archivePath "$ARCHIVE_PATH" \
            -exportPath "$EXPORT_PATH" \
            -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
            -allowProvisioningUpdates; then
            EXPORT_OK=true
        fi
    fi

    # Find the actual IPA — name may differ from expected
    if [ "$EXPORT_OK" = "true" ]; then
        FOUND_IPA=$(find "$EXPORT_PATH" -name "*.ipa" -print -quit 2>/dev/null)
        if [ -n "$FOUND_IPA" ]; then
            IPA_PATH="$FOUND_IPA"
        fi
        echo -e "${GREEN}IPA exported successfully${NC}"
        echo "  Location: $IPA_PATH"
    else
        echo -e "${RED}IPA export failed${NC}"
        SKIP_UPLOAD=true
    fi
}

upload_to_testflight() {
    if [ "$SKIP_UPLOAD" = true ]; then
        echo ""
        echo -e "${YELLOW}Skipping upload (no API credentials)${NC}"
        echo "You can manually upload the IPA from:"
        echo "  $IPA_PATH"
        echo ""
        echo "Using Xcode:"
        echo "1. Open Xcode -> Window -> Organizer"
        echo "2. Drag the IPA file to the Organizer"
        echo "3. Click 'Distribute App'"
        return
    fi

    echo ""
    echo "Uploading to TestFlight..."

    # Create API key file if needed
    if [ ! -f "$API_KEY_PATH" ] && [ -n "$APPSTORE_PRIVATE_KEY" ]; then
        mkdir -p "$HOME/private_keys"
        echo "$APPSTORE_PRIVATE_KEY" > "$API_KEY_PATH"
    fi

    UPLOAD_OK=false

    # Prefer iTMSTransporter; fall back to altool
    if xcrun --find iTMSTransporter >/dev/null 2>&1; then
        if xcrun iTMSTransporter \
            -m upload \
            -assetFile "$IPA_PATH" \
            -apiKey "$API_KEY_ID" \
            -apiIssuer "$API_ISSUER_ID" \
            -v informational; then
            UPLOAD_OK=true
        fi
    fi

    if [ "$UPLOAD_OK" != "true" ]; then
        if xcrun altool --upload-app \
            -f "$IPA_PATH" \
            --apiKey "$API_KEY_ID" \
            --apiIssuer "$API_ISSUER_ID"; then
            UPLOAD_OK=true
        fi
    fi

    if [ "$UPLOAD_OK" = "true" ]; then
        echo -e "${GREEN}SUCCESS! App uploaded to TestFlight${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Wait for processing in App Store Connect"
        echo "2. Go to App Store Connect -> TestFlight"
        echo "3. Add test information if needed"
        echo "4. Share with testers!"
    else
        echo -e "${RED}Upload failed${NC}"
        echo "Try uploading manually through Xcode Organizer"
        SKIP_UPLOAD=true
    fi
}

show_summary() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
    echo "Summary:"
    echo "  Build Number: $NEW_BUILD"
    echo "  Archive: $(basename "$ARCHIVE_PATH")"
    echo "  IPA: $IPA_PATH"
    if [ "$SKIP_UPLOAD" != true ]; then
        echo "  Status: Uploaded to TestFlight"
    else
        echo "  Status: Ready for manual upload"
    fi
    echo ""
    echo "Useful links:"
    echo "  App Store Connect: https://appstoreconnect.apple.com"
    echo "  TestFlight: https://testflight.apple.com"
    echo ""
}

# ========== Main Script ==========

print_header

# Run deployment steps
check_prerequisites
increment_build_number
clean_build
build_archive
export_ipa
upload_to_testflight
show_summary
