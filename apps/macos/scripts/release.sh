#!/bin/sh
# Builds a DISTRIBUTABLE, notarized voz.dmg — the thing people download and double-click.
#
# Requires (one-time): a "Developer ID Application" cert in your Keychain, and notarization creds
# stored under a profile (default: voz-notary) via:
#   xcrun notarytool store-credentials voz-notary --apple-id <id> --team-id <team> --password <app-specific-pw>
#
# No secrets live in this repo — the cert's private key + the notary password stay in your Keychain.
set -e
cd "$(dirname "$0")/.."

PROFILE="${VOZ_NOTARY_PROFILE:-voz-notary}"
DEVID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -z "$DEVID" ]; then
  echo "✗ No 'Developer ID Application' certificate in your Keychain."
  echo "  Create one: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application."
  exit 1
fi
echo "Signing identity: $DEVID"
APP="build/voz.app"

# 1. Assemble the .app (build + icon + strip), signed with the Developer ID cert.
VOZ_SIGN_ID="$DEVID" sh scripts/bundle.sh

# 2. Re-sign with the HARDENED RUNTIME + secure timestamp + entitlements (notarization requires all three).
codesign --force --options runtime --timestamp --entitlements voz.entitlements -s "$DEVID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist

# 3. Notarize the app (Apple scans it, then we staple the ticket so it works offline).
ZIP="dist/voz-$VER.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "→ Notarizing the app (Apple, ~1–3 min)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

# 4. Build a BRANDED, drag-to-install DMG: voz.app + an Applications shortcut, a dark background with
#    an arrow, and fixed icon positions — like a commercial Mac app. Styling is applied via Finder; if
#    that isn't permitted (the first run prompts to allow controlling Finder — grant it once), it
#    gracefully falls back to a plain, still-notarizable DMG.
DMG="dist/voz-$VER.dmg"
[ -f media/dmg-bg.png ] || swift scripts/make-dmg-bg.swift media/dmg-bg.png || true
STAGE="build/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/voz.app"
ln -s /Applications "$STAGE/Applications"
[ -f media/dmg-bg.png ] && cp media/dmg-bg.png "$STAGE/.background/bg.png"

RW="build/voz-rw.dmg"; rm -f "$RW" "$DMG"
hdiutil create -volname "voz" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MOUNT="$(hdiutil attach "$RW" -nobrowse -noautoopen | grep -o '/Volumes/voz[^[:cntrl:]]*' | head -n1)"
if [ -n "$MOUNT" ] && [ -f "$STAGE/.background/bg.png" ]; then
  osascript <<'OSA' 2>/dev/null || echo "  ↳ Finder styling skipped — grant Automation → Finder once, then re-run for the branded layout."
tell application "Finder"
  tell disk "voz"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set background picture of opts to file ".background:bg.png"
    set position of item "voz.app" of container window to {150, 205}
    set position of item "Applications" of container window to {450, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
  sync; sleep 1
fi
[ -n "$MOUNT" ] && hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
hdiutil convert "$RW" -format UDZO -ov -o "$DMG" >/dev/null
rm -f "$RW"

# 5. Sign, notarize, and staple the DMG itself.
codesign --force --timestamp -s "$DEVID" "$DMG"
echo "→ Notarizing the DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo
echo "✓ Notarized, ready to ship: $DMG"
spctl -a -vv -t install "$DMG" 2>&1 || true
echo "Upload with:  gh release create v$VER \"$DMG\" --title \"voz $VER\" --notes \"…\""
