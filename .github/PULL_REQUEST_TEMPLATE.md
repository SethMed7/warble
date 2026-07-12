## What this changes, and why

<!-- The "why" matters more than the "what" — link an issue if there is one. -->

## The regression gate

- [ ] `sh scripts/regression.sh` passes locally (CI re-runs it, but it should already be green
      when you open this PR — see [docs/testing.md](../docs/testing.md))
- [ ] If this adds or changes behavior, I extended `scripts/regression.sh` with a check that
      proves it (or, if it genuinely can't be headless, added its by-hand procedure to
      [docs/testing.md](../docs/testing.md)'s manual-tests list)

## Docs ship with code

- [ ] **README.md** updated, if this changes what a user sees or does
- [ ] **CHANGELOG.md** — a bullet added under `## Unreleased` describing what a user actually gets
- [ ] N/A — this is internal-only (tests, CI, docs-only, refactor with no behavior change)

## The ground rules ([CONTRIBUTING.md](../CONTRIBUTING.md))

- [ ] No new network behavior beyond the three disclosed ones
      ([docs/transparency.md](../docs/transparency.md)) — no telemetry, no accounts
- [ ] Any UI change follows [DESIGN.md](../DESIGN.md) and, where applicable, renders through an
      existing (or new) headless render seam
- [ ] Any public claim/number this PR adds or changes is measured end-to-end and reproducible
      (product.md §4.9) — not estimated
