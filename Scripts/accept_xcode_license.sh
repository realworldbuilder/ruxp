#!/bin/bash

# Script to accept Xcode license
echo "Attempting to accept Xcode license..."

# Check if we can run xcodebuild -version (this sometimes works even without license)
if xcodebuild -version > /dev/null 2>&1; then
    echo "✅ Xcode license already accepted or xcodebuild working"
    exit 0
fi

# Try to accept license
echo "Need to accept Xcode license..."
echo "Please run this command manually with admin privileges:"
echo "sudo xcodebuild -license accept"
echo ""
echo "Or interactively view and accept:"
echo "sudo xcodebuild -license"
echo ""
echo "After accepting the license, run this script again to verify."

exit 1