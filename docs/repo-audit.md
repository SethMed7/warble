# warble — repository history audit

*ROADMAP 0.7's history audit: REPORT-ONLY, per the ground rule that governs it — this document
finds and rates, it never rewrites. Any squash/scrub of git history is explicitly the owner's
call, not something this audit performs or recommends performing without that sign-off. Written
2026-07-12 against `main` at commit `c849097` (84 commits total, `c57ec93` .. `c849097`,
2026-06-15 .. 2026-07-12; single branch — release tags `v0.1.0`–`v0.1.6` (`git for-each-ref`) all
sit on the main line, verified with `git merge-base --is-ancestor <tag> main` for each). Every
command below is exactly what was run — re-run any of them yourself; that's the point.*

## Method

Two passes: (1) `git log --all -p` over the **entire history**, not just the current tree, since a
secret committed and later deleted is still in every clone; (2) a look at the actual **shipped
artifact** — `gh release download v0.2.0 -p '*.dmg'`, the notarized `warble-0.2.0.dmg` fetched
fresh from the GitHub release, not the gitignored local `apps/macos/dist/` copy a build happens to
leave behind — with `strings`, because a stranger auditing this project (the milestone's own bar —
"an adversarial stranger armed with Little Snitch, `strings`, and the transparency doc") checks the
binary they can actually download, not a local build artifact they won't have. (The local
`apps/macos/dist/warble-0.2.0.dmg` happens to be byte-identical to the published asset —
`sha256 3bf3edb165230be73e1c69aaea79f2558d4d595e88f55ccf402b8aa060c29d6c` both ways — but that is
not true of every release: `apps/macos/dist/voz-0.1.6.dmg`, for instance, is a stale local build
(1,226,879 B, and it still carries the `/Users/sethmedina/...` path string) that does not match
the published v0.1.6 asset (1,193,447 B, string-free) — so §7's commands always fetch the release
asset rather than assume the local `dist/` copy matches it.)

## Verdict

**Fine to open source as-is.** Nothing found rises to scrub-before-public. One low-severity,
real finding (§7 below) was surfaced by this audit and is now proactively disclosed in
[docs/transparency.md](transparency.md#release-integrity) rather than left for someone else to
find first — which is the whole point of running this audit before the repo goes public instead
of after.

## Findings

### 1. Secrets, keys, tokens — none found

```sh
git log --all -p | grep -nEi \
  'AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----|api[_-]?key["'"'"':= ]|secret[_-]?key|access[_-]?token|Bearer [A-Za-z0-9._-]{20,}|ghp_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{20,}|password\s*=\s*["'"'"'][^"'"'"']{3,}'
git log --all --pretty=format: --name-only --diff-filter=A | sort -u | \
  grep -Ei '\.env|secret|\.pem$|\.key$|\.p12|\.p8$|credential|\.netrc|id_rsa|\.certSigningRequest|\.mobileprovision|notarize\.cfg'
```

Zero hits, either pattern. No `.env`, `.p12`, `.p8`, certificate, or credential-shaped filename
was ever committed. The Sparkle EdDSA **private** key that signs updates was never committed —
only `SUPublicEDKey` (the public half) lives in `Info.plist`, exactly as
[docs/transparency.md](transparency.md) and `apps/macos/scripts/update-appcast.sh`'s own comments
say it should (`generate_keys`; the private key stays in the maintainer's login Keychain). The
notary/signing setup comments (`release.sh`) use literal placeholders (`<id>`, `<team>`) — no real
Apple ID, Team ID, or app-specific password ever appears.

**Severity: clean.**

### 2. Personal absolute paths in committed source/docs — none found

```sh
git log --all -p | grep -oE '/Users/[A-Za-z0-9_.-]+' | sort -u
```

Zero hits across every revision of every file. No committed source, script, test fixture, or doc
ever hardcoded `/Users/sethmedina/...` or any other developer-machine path. (Contrast with §7,
which is a *build-artifact* finding, not a committed-history one — the distinction matters because
this audit's remit is history, and no history rewrite would fix §7 anyway.)

**Severity: clean.**

### 3. Emails beyond the committer's — none found

```sh
git log --all --pretty=format:'%ae|%ce' | sort -u
git log --all -p | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | sort -u
```

Every commit's author/committer email is the single GitHub-provided noreply address
(`133716309+SethMed7@users.noreply.github.com`) — itself already privacy-preserving; Seth's real
address is never the git identity. The only other addresses appearing anywhere in file *content*
across all of history are `enterprise@wisprflow.ai` (Wispr Flow's own public support address,
quoted verbatim in the competitive teardown, `docs/competitive/`) and `noreply@anthropic.com`
(the `Co-Authored-By:` trailer this workflow adds to commits) — both expected, both public,
neither personal.

**Severity: clean.**

### 4. Internal hostnames / non-loopback IPs — none found

```sh
git log --all -p | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | sort -u | grep -v '^127\.0\.0\.1$'
git log --all -p | grep -oiE '\b[a-z0-9.-]+\.(internal|local|corp|lan|vpn)\b' | sort -u
```

Zero hits either way. Every IP literal in the codebase is `127.0.0.1` (the loopback engines,
already fully disclosed in `docs/transparency.md`); no `*.internal`/`*.corp`/`*.lan`/`*.vpn`-style
hostname, no Myela/MSD infrastructure hostname, ever appears.

**Severity: clean.**

### 5. Stray/embarrassing content — none found

```sh
git log --all --pretty=format: --name-only --diff-filter=A | sort -u | \
  grep -Ei '~$|\.orig$|\.bak$|\.swp$|\.log$|\.DS_Store'
git log --all -p | grep -inE '^\+.*\b(TODO|FIXME|XXX|HACK)\b'
```

No editor backup files, no `.DS_Store`, no stray log files were ever committed. No `TODO`/`FIXME`/
`XXX`/`HACK` comment was added and later needed removing before this audit — the working tree's
current comments (if any) are ordinary engineering notes, not personal or sensitive. The largest
blobs in history (`git rev-list --objects --all` + `cat-file --batch-check`) are exactly the
expected brand/marketing PNGs (`icon.png`, `logo.png`, `watermark.png`, `insights.png`,
`dmg-bg.png`, `showcase.png`, `banner.png`, `brand.png`, `v-mark.png`) — nothing unaccounted for.

**Severity: clean.**

### 6. Predecessor-project history (leelo + dictado) — cleanly squashed, nothing imported

warble began as a blend of two prior standalone apps (`leelo` — read aloud, `dictado` — dictate).
The very first commit in this repo, `c57ec93` ("voz 0.1.0 — blend leelo + dictado into one
on-device voice app"), is the blended starting point — there is no earlier, granular commit
history from either predecessor repo folded in underneath it (`71f8615`, a few commits later,
explicitly de-links the now-private leelo/dictado repos from the README). Whatever those two
repos' own separate histories contain is out of this audit's scope by construction: it was never
merged into `warble`'s object graph.

**Severity: clean** (informational — explains why history starts at a "blend" commit rather than
two separate app histories).

### 7. A real, low-severity personal-path leak — in the shipped *binary*, not git history

The ground truth to verify was: *"the 0.3-era strip-before-codesign work already removed binary
path leaks."* Checking it turned up a correction worth stating precisely:

- `strip -S "$APP/Contents/MacOS/warble"` (`apps/macos/scripts/bundle.sh`) has been present since
  the **very first commit** (`c57ec93`, 0.1.0) — it is not 0.3-era work, and `git log -S'strip -S'
  --all -- apps/macos/scripts/bundle.sh` confirms no other commit ever touched that line. `strip
  -S` does its job: it removes the debug symbol table, which is what would otherwise carry
  build-machine paths to intermediate `.o` files. Comparing the **unstripped debug binary** (3
  embedded `/Users/sethmedina/...` paths — the resource-bundle fallback plus two source-file
  paths baked in by Swift's runtime-trap diagnostics) against the **actual stripped, signed,
  notarized release binary** confirms `strip -S` + the release build configuration together
  eliminate two of those three:

  ```sh
  # debug (unstripped): 3 hits
  strings apps/macos/.build/debug/warble | grep -c '/Users/[A-Za-z0-9_.-]\+'

  # the REAL shipped release binary — fetched fresh from the GitHub release, not the local dist/
  # copy (see Method above: a stale local dist/ dmg can silently disagree with what was published)
  gh release download v0.2.0 -p '*.dmg' -D /tmp/warble-dmg-check --clobber
  hdiutil attach /tmp/warble-dmg-check/warble-0.2.0.dmg -mountpoint /tmp/warble-dmg-mount -nobrowse -quiet
  strings /tmp/warble-dmg-mount/warble.app/Contents/MacOS/warble | grep -E '/Users/[A-Za-z0-9_.-]+'
  hdiutil detach /tmp/warble-dmg-mount -quiet
  ```

  The release binary result: **exactly one** embedded absolute path —
  `/Users/sethmedina/warble/apps/macos/.build/arm64-apple-macosx/release/warble_Shared.bundle`.

- **Source:** this is not warble's own code. It's SwiftPM's auto-generated
  `resource_bundle_accessor.swift` (one is synthesized per resource-bearing target;
  `apps/macos/.build/*/release/Shared.build/DerivedSources/resource_bundle_accessor.swift`),
  standard boilerplate the Swift toolchain writes for every SPM package with `resources:` —
  the exact same pattern ships in countless open-source SwiftPM apps. It embeds the absolute
  build-directory path as a **fallback** constant, reached only if the primary lookup (relative
  to the running app's own bundle) fails — which it never does in the shipped app; the string is
  functionally dead code at runtime, but it is compiled into the binary's read-only data and
  `strings` finds it regardless of whether it ever executes.
- **What it discloses:** the local macOS account name (`sethmedina`) and the repo's on-disk
  directory name (`warble/apps/macos/...`) at build time — a mildly identifying detail, no secret,
  no credential, no capability. It is unaffected by `strip -S` (which strips the symbol table, not
  string constants compiled from source) and would reappear identically in *any* future SwiftPM
  release built from the same local path.
- **Recommendation: informational, not scrub-before-public.** No fix is required before opening
  the repo — the string carries no exploitable information and is unremarkable to anyone who
  recognizes SwiftPM's own generated code. The precise, `product.md §4.9`-consistent move is the
  one already taken this step: **name it before a stranger finds it** — it's now disclosed in
  [docs/transparency.md's Release Integrity section](transparency.md#release-integrity) alongside
  the other honest limits on build reproducibility. If a future maintainer wants it gone entirely,
  the options are (a) building releases from a fixed, non-personal path (e.g.
  `/Users/builder/warble` or a CI runner, which only relocates the string, doesn't remove it), or
  (b) a post-strip binary patch replacing the string bytes with a same-length placeholder before
  codesigning — neither is scoped into this step.

**Severity: low / informational.** Corrects the ground-truth claim from "already removed" to
"partially removed by `strip -S` since 0.1.0, with one SwiftPM-generated string it can't reach —
now disclosed rather than silently present."

## Backfilling checksums for the ten pre-0.7 releases

Separate from the history audit itself, but the same "state it precisely" discipline: `v0.1.0`
through `v0.1.8` and `v0.2.0` (ten releases, verified via `gh release list`) each carry a signed,
notarized `.dmg` asset and **no** `checksums.txt` — the checksum step ships starting this
milestone (0.7), so it never ran for them. Backfilling is safe (hashing an already-published,
already-notarized file changes nothing about it) and the exact commands, per release, are:

```sh
gh release download v0.1.0 -p '*.dmg' -D /tmp/warble-backfill
sh apps/macos/scripts/checksum.sh /tmp/warble-backfill/voz-0.1.0.dmg /tmp/warble-backfill/checksums.txt
gh release upload v0.1.0 /tmp/warble-backfill/checksums.txt
# repeat for v0.1.1 .. v0.1.8, v0.2.0 (asset names: voz-0.1.x.dmg through 0.1.8, warble-0.2.0.dmg)
```

This audit does not run those uploads itself — mutating already-published GitHub releases is a
production action outside an implementer step's scope, and the ROADMAP explicitly leaves the
timing to the owner ("covers all ten dmg-bearing releases or states an explicit owner decision to
backfill fewer"). Stated explicitly: **all ten are eligible and the commands above cover all ten;
whether/when to run them is Seth's call, not made here.**
