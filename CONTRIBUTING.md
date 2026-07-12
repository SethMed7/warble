# Contributing to warble

warble is a solo-maintained, 100% on-device macOS app — see [docs/product.md](docs/product.md)
for what it is and isn't, and [ROADMAP.md](ROADMAP.md) for where it's headed. Contributions are
welcome; this page is the practical how-to.

## Ground rules first

- **No cloud, ever.** Nothing you add may phone anything beyond the three disclosed network
  behaviors ([docs/transparency.md](docs/transparency.md)): the Sparkle update check, consented
  model downloads in Setup, and loopback-only (`127.0.0.1`) links to warble's own local engines.
  No telemetry, no analytics, no "just for crash reports" exception.
- **No accounts.** Nothing to log into, nothing to sync, nothing to breach.
- **Precision in every claim** (product.md §4.9). If your change touches a number, a comparison,
  or a claim about what warble does, it must be measured end-to-end and reproducible — no
  aspirational rounding.
- Every PR needs @SethMed7's review (`.github/CODEOWNERS` + branch protection enforce this) —
  it's a solo-maintainer project, not a bottleneck to route around.

## Build it

```sh
cd apps/macos
swift build                # debug build
sh scripts/bundle.sh        # release -> build/warble.app (unsigned)
sh scripts/install.sh       # build, sign (if you have a cert), install to /Applications, launch
```

No signing certificate needed just to build and run `swift build`'s debug binary — signing only
matters for a distributable `.dmg` (see "Cutting a release" in [README.md](README.md#development)).

## Run the suite before you open a PR

```sh
sh scripts/regression.sh
```

This is **the** gate — one deterministic command, engine-free by default (no premium engines, no
Speech authorization, no UI required), that exits `0` only when every check passes. It's the same
command CI runs on every push to `main` and every PR (`.github/workflows/regression.yml`). The full coverage map,
every env/render seam, and what still needs a human (headed by the fresh-account five-minute test
and the Little Snitch silence test) is [docs/testing.md](docs/testing.md).

```sh
sh scripts/regression.sh --list              # see every check, and what it proves
sh scripts/regression.sh --only <check>      # iterate on one check fast
WARBLE_REGRESSION_FULL=1 sh scripts/regression.sh   # + warm-engine extras (needs premium engines installed)
```

**A feature without a regression check is incomplete.** If you're adding behavior, extend
`scripts/regression.sh` with a check that proves it (see "Adding a check" at the bottom of
[docs/testing.md](docs/testing.md)) — or, if it genuinely can't be headless (needs a mic, a
screen, or a live gesture), add its by-hand procedure to that doc's manual-tests list instead of
skipping coverage entirely.

## Design law

Any UI change reads [DESIGN.md](DESIGN.md) first — it's the machine-readable design law (colors,
type, motion rules) distilled from [brand/tokens.md](brand/tokens.md) and the product principles
in [docs/product.md](docs/product.md) §4. The short version: one electric-blue accent on black,
motion only when voice moves, nothing persistent by default. Render new UI states through the
existing headless render seams (`--render-onboarding`, `--render-pill`, `--render-setup`, …) so
`scripts/onboarding-gallery.sh` can catch a card that's missing from design review, and so the
regression suite can assert real pixels instead of trusting a screenshot.

## Code style

- Minimal abstraction, short focused functions, match the surrounding idiom — see the root
  `CLAUDE.md` conventions if you're curious where this comes from.
- TypeScript in `core/` stays strict-mode, dependency-light, and cross-platform (no Apple APIs —
  it's the portable layer a non-macOS shell could embed someday).
- Swift in `apps/macos/` stays split across its existing modules (`Shared`, `Speak`, `Dictate`,
  the `warble` executable) — don't reach across a module boundary that doesn't already exist
  without a reason.

## Commit style: docs ship with code

If a change is user-visible, its documentation ships **in the same commit/PR**, not a follow-up:
- **README.md** — if the change affects what a user sees or does, the relevant section updates.
- **CHANGELOG.md** — add a bullet under `## Unreleased` describing what a user actually gets, in
  the same step. (See the existing entries for the tone: what changed and why it matters, not an
  implementation diary.)

A PR that changes behavior without touching these is asked to add them, not merged around it.

## Reporting bugs / requesting features

Use the issue templates (`.github/ISSUE_TEMPLATE/`) — they ask for exactly what's needed to
reproduce or evaluate, nothing more. Security-relevant findings (a hook or network behavior not
covered by [docs/transparency.md](docs/transparency.md)) are also just regular issues — there's no
separate private channel, because there's no separate private thing to protect: no accounts, no
servers, no user data warble itself holds.

## What review checks

Every PR: does `sh scripts/regression.sh` pass (CI runs it, but run it locally first), does the
change match the ground rules above, and do the docs ship with it. See
`.github/PULL_REQUEST_TEMPLATE.md` for the checklist a PR description is expected to walk through.
