#!/bin/sh
# Add a release to the Sparkle appcast so warble's in-app updater can offer it. Run AFTER release.sh has
# built the notarized DMG and you've created the GitHub release that hosts it.
#
#   sh scripts/update-appcast.sh <version> <path-to-dmg>
#   e.g. sh scripts/update-appcast.sh 0.1.7 dist/warble-0.1.7.dmg
#
# It signs the DMG with your EdDSA private key (login Keychain) via Sparkle's sign_update, then prepends
# an <item> to appcast.xml pointing at the GitHub release asset. Commit + push appcast.xml to publish.
set -e
cd "$(dirname "$0")/.."                                   # apps/macos
VER="$1"; DMG="$2"
[ -n "$VER" ] && [ -f "$DMG" ] || { echo "usage: sh scripts/update-appcast.sh <version> <path-to-dmg>"; exit 1; }

ROOT="$(git rev-parse --show-toplevel)"
APPCAST="$ROOT/appcast.xml"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$SIGN_UPDATE" ] || { echo "✗ sign_update missing — run 'swift build' first (it fetches Sparkle's tools)."; exit 1; }
[ -f "$APPCAST" ] || { echo "✗ $APPCAST not found."; exit 1; }

# sign_update prints the enclosure signature attributes, e.g.:  sparkle:edSignature="…" length="123"
SIG_ATTRS="$("$SIGN_UPDATE" "$DMG")"
URL="https://github.com/SethMed7/warble/releases/download/v$VER/$(basename "$DMG")"

VER="$VER" URL="$URL" SIG_ATTRS="$SIG_ATTRS" APPCAST="$APPCAST" python3 - <<'PY'
import os, datetime, email.utils
ver = os.environ["VER"]; url = os.environ["URL"]
sig = os.environ["SIG_ATTRS"].strip(); path = os.environ["APPCAST"]
pub = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
item = f'''    <item>
      <title>warble {ver}</title>
      <sparkle:version>{ver}</sparkle:version>
      <sparkle:shortVersionString>{ver}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <link>https://github.com/SethMed7/warble/releases/tag/v{ver}</link>
      <pubDate>{pub}</pubDate>
      <enclosure url="{url}" sparkle:version="{ver}" {sig} type="application/octet-stream" />
    </item>'''
marker = "<!-- APPCAST-ITEMS:"
src = open(path).read()
if marker not in src:
    raise SystemExit("✗ APPCAST-ITEMS marker not found in appcast.xml")
i = src.index(marker); eol = src.index("\n", i) + 1
open(path, "w").write(src[:eol] + item + "\n" + src[eol:])
print(f"✓ appcast.xml updated for warble {ver}")
print(f"  enclosure: {url}")
PY
echo "Next: from the repo root,  git add appcast.xml && git commit -m \"appcast: warble $VER\" && git push"
