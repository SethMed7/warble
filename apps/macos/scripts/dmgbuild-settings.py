# dmgbuild settings for the warble DMG — builds a styled, branded disk image WITHOUT Finder/AppleScript
# (it writes the .DS_Store programmatically), so it works headlessly / in CI with no Automation grant.
# Driven by release.sh via env vars:  WARBLE_APP=/abs/warble.app  WARBLE_BG=/abs/dmg-bg.png
import os

application = os.environ["WARBLE_APP"]
appname = os.path.basename(application)        # "warble.app"

# Contents: the app + an Applications symlink.
files = [application]
symlinks = {"Applications": "/Applications"}

# Compressed, ready to sign + notarize.
format = "UDZO"

# Window + icon layout (must match the arrow/positions drawn in make-dmg-bg.swift; origin top-left).
background = os.environ["WARBLE_BG"]
window_rect = ((220, 120), (600, 420))
default_view = "icon-view"
icon_size = 116
text_size = 13
# y=196 (matches rowY in make-dmg-bg.swift) sits the icon+label group at the optical vertical center.
icon_locations = {
    appname: (150, 196),
    "Applications": (450, 196),
}
