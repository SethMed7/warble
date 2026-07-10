# warble in-app updates — Sparkle

How warble updates itself without anyone visiting GitHub: an in-app **Check for Updates…** plus a quiet
daily background check, with secure (EdDSA-signed) download → replace → relaunch. Powered by
[Sparkle](https://github.com/sparkle-project/Sparkle), warble's only external dependency.

## How it works
- **App side.** `AppDelegate` owns an `SPUStandardUpdaterController(startingUpdater: true)`. The
  "Check for Updates…" menu item targets it; `startingUpdater: true` runs the scheduled checks. Sparkle
  reads the feed (`SUFeedURL`) over HTTPS, verifies every download against the embedded EdDSA public key
  (`SUPublicEDKey`), and installs in place. `SUEnableAutomaticChecks` + a 1-day interval = the quiet check.
- **Feed.** `appcast.xml` at the repo root, served at
  `https://raw.githubusercontent.com/SethMed7/warble/main/appcast.xml` (public repo → no auth, no hosting to
  set up). Each `<item>` points at that version's GitHub release DMG and carries its EdDSA signature.
- **Privacy.** Version info only — no accounts, no telemetry. This is the *second* (and only other)
  network path warble has, alongside the opt-in model download; the README Privacy section discloses it.

## Build/signing wiring (done)
- `Package.swift` — Sparkle dependency on the `warble` target only (`core/` + capability modules stay
  dependency-free).
- `Info.plist` — `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`.
- `scripts/bundle.sh` — embeds `Sparkle.framework` into `Contents/Frameworks/` and adds the
  `@executable_path/../Frameworks` rpath (the SwiftPM binary links it via `@rpath`).
- `scripts/release.sh` — signs Sparkle's nested helpers + XPC services + framework with the **hardened
  runtime** (inside-out) before signing the app, so notarization passes.

## One-time setup (status)
- **EdDSA keypair — DONE.** Generated with Sparkle's `generate_keys`; the private key lives in the
  maintainer's login Keychain, the public key is in `Info.plist` (`SUPublicEDKey`). Never commit the
  private key. To recover/rotate: `generate_keys -p` prints the current public key.
- **Feed — DONE.** `appcast.xml` skeleton committed; it publishes the moment it's pushed to `main`.

## Per-release runbook
1. Bump the version: `CFBundleShortVersionString` **and** `CFBundleVersion` in `apps/macos/Info.plist`
   (and the `--version` fallback in `Sources/warble/main.swift`).
2. `sh scripts/release.sh` — builds, notarizes, and staples `dist/warble-<ver>.dmg`.
3. `gh release create v<ver> dist/warble-<ver>.dmg --title "warble <ver>" --notes "…"` — hosts the DMG.
4. `sh scripts/update-appcast.sh <ver> dist/warble-<ver>.dmg` — signs the DMG + prepends the `<item>`.
5. Commit + push `appcast.xml` — that's the moment every install sees the update.

## Validation status
- ✅ Sparkle resolves via SwiftPM (2.9.3) and compiles into the app (`swift build`, debug + release).
- ✅ `bundle.sh` embeds the framework; signature validates including nested Autoupdate / Updater.app /
  Installer.xpc / Downloader.xpc; `warble --version` loads the embedded framework via dyld (exit 0).
- ⚠️ **End-to-end not yet confirmed** — an actual update can only be proven once the first Sparkle build
  (≥ v0.1.7) is released and its appcast item is pushed. Existing 0.1.6 installs predate Sparkle, so they
  won't auto-update; the first Sparkle release is installed manually once, then updates are automatic.
