#!/usr/bin/env bash
# deploy-testflight.sh — archive Blur and push it to TestFlight.
#
# Needs the App Store Connect API key (already on disk) plus its Issuer ID,
# which lives only in your ASC account:
#   App Store Connect → Users and Access → Integrations → App Store Connect API
#   → the Issuer ID shown at the top of that page (a UUID).
#
# Usage:
#   ASC_ISSUER_ID=<uuid> ./deploy-testflight.sh
#
# xcodebuild talks to ASC with the key (-allowProvisioningUpdates), so it
# creates the Distribution certificate, registers the ag.nuke.blur App ID, and
# builds the App Store provisioning profile automatically — no manual Xcode step.
set -euo pipefail

cd "$(dirname "$0")"

KEY_ID="77637BYL66"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
ISSUER="${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (App Store Connect → Users and Access → Integrations → Issuer ID)}"

ARCHIVE="build/Blur.xcarchive"
EXPORT_DIR="build/export"

echo "▸ Regenerating project (stamps a fresh monotonic build number)…"
./generate.sh >/dev/null

echo "▸ Archiving (Release)…"
xcodebuild archive \
  -project Blur.xcodeproj \
  -scheme Blur \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER"

echo "▸ Exporting .ipa…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER"

IPA="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
echo "▸ Uploading $IPA to App Store Connect / TestFlight…"
xcrun altool --upload-app \
  -f "$IPA" \
  -t ios \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER"

echo "✅ Uploaded. It processes for a few minutes, then appears in TestFlight."
echo "   Assign it to the 'Nuke' internal group there (or turn on automatic"
echo "   distribution for that group) and it installs on your phone."
