#!/bin/sh
# Builds and installs warble to /Applications — the stable home the permission grants
# are tied to. Rebuilding re-signs the app; with a stable identity (see bundle.sh)
# the Accessibility / Microphone grants carry over.
set -e
cd "$(dirname "$0")/.."
sh scripts/bundle.sh
killall warble 2>/dev/null || true
rm -rf /Applications/warble.app
ditto build/warble.app /Applications/warble.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/warble.app
open /Applications/warble.app
echo "Installed and launched /Applications/warble.app"
echo "Each capability prompts only for what it needs the first time you use it:"
echo "  • Read aloud (⌃V): Accessibility (to read your selection)"
echo "  • Dictate (hold Fn): Microphone + Accessibility (to type the result)"
