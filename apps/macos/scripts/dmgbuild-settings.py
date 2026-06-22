# dmgbuild settings for the voz DMG — builds a styled, branded disk image WITHOUT Finder/AppleScript
# (it writes the .DS_Store programmatically), so it works headlessly / in CI with no Automation grant.
# Driven by release.sh via env vars:  VOZ_APP=/abs/voz.app  VOZ_BG=/abs/dmg-bg.png
import os

application = os.environ["VOZ_APP"]
appname = os.path.basename(application)        # "voz.app"

# Contents: the app + an Applications symlink.
files = [application]
symlinks = {"Applications": "/Applications"}

# Compressed, ready to sign + notarize.
format = "UDZO"

# Window + icon layout (must match the arrow/positions drawn in make-dmg-bg.swift; origin top-left).
background = os.environ["VOZ_BG"]
window_rect = ((220, 120), (600, 440))
default_view = "icon-view"
icon_size = 116
text_size = 13
icon_locations = {
    appname: (150, 220),
    "Applications": (450, 220),
}
