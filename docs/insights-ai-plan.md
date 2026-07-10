# warble Insights AI — build plan

Phase 5 of `docs/insights-plan.md`: an **optional, on-device** layer that turns the local stats into a
**weekly summary**, **suggested dictionary words**, and **nudges**. Behind a **default-off master
switch**, cached, user-controlled, and graceful when the model isn't installed. **100% on-device** —
the same warm MLX server that polishes dictation, never the network.

## What ships (all three, one release)
1. **Weekly summary** — 2–3 warm sentences over the week: words dictated, busiest apps, pace trend, streak.
2. **Suggested dictionary words** — "you keep fixing *devil → Dhaval* — make it a rule?", one-tap Accept.
3. **Nudges** — computed insights ("6-day streak — one more for a week"; "you dictate 40% faster in Slack
   than Mail"), phrased warmly.

## Principles
- **Reuse, don't build.** The hard parts already exist (warm MLX server + computed aggregates). This slice
  is wiring + prompt + cache + one UI surface.
- **The LLM is the phrasing layer, not the engine.** Suggestions and nudges are computed deterministically
  from data we already have; the model only makes them readable. The summary is the one truly generative
  piece — and it summarizes *numbers*, so the small 1.5B model is sufficient.
- **Nothing runs without you.** Default-off master switch; once on, you choose auto-refresh or on-demand.

## Architecture — reuse (unchanged)
- **Model call:** `WarmLLM.shared.clean(system:text:timeout:)` → warm MLX server (`core/llm-server.py`,
  Qwen2.5-1.5B-Instruct-4bit, offline, idle-exits 600s). Generic `system + text → text`.
- **Availability:** `WarmLLM.isInstalled()` gates the whole feature — no model installed → AI cards hidden.
- **Data:** `InsightStore` already exposes `totalWords · avgWPM · dayStreak · perApp · wordsPerDay ·
  wpmPerDay · events`. Feed **aggregates**, not the raw log.
- **Dictionary writes:** `Lexicon.shared.learn(from:to:)` + the existing sub-threshold `pending` tally.
- **UI styling:** `.cardStyle()` · `WarbleTheme` · `StatCard` patterns.

## Architecture — new
- **`Sources/Dictate/Insights/AIInsights.swift`** — `AIInsightsStore: ObservableObject`. Builds the prompt
  from `InsightStore` aggregates, calls `WarmLLM` off the main thread, parses, and **caches to
  `~/.warble/insights-ai.json`** (`{generatedAt, windowHash, summary, nudges[], suggestions[]}`). Master-switch
  gated: off → never spawns or calls the model.
- **Cards in the Insights tab** (`InsightsView.swift`) — summary card · suggestions list (Accept/Dismiss →
  `Lexicon.learn`) · nudge chips, above the existing charts. No new sidebar row. When AI is off, an inline
  "Turn on Insights AI" enable card sits in their place.
- **Master switch + mode** — `InsightStore.aiInsightsEnabled` (default **false**) and
  `aiInsightsAutoRefresh` (default **on once enabled**), surfaced in `DataPrivacyView`.

## Generation & caching (user-controlled)
- **Auto** (default once enabled): regenerate when the Insights tab opens and the cache is empty or its
  `windowHash`/age is stale (>7 days). Off the main thread; show a "generating…" state. First call waits
  out the one-time model load (~1–2s, the warm server handles re-warm).
- **On-demand**: never auto-generates; a "Generate summary" / "Regenerate" button is the only trigger.
- Either way the cache is a plain local JSON file you can read, export, or delete — nothing hidden.

## Suggested-words sourcing
1. **`Lexicon.pending`** (deterministic, works in stats-only mode) — corrections made but not yet promoted.
   Highest signal, no model. **Ship first within 5b.**
2. **Model OOV detection** (needs `historyEnabled`) — proper-noun / out-of-vocab candidates from recent
   transcripts. Layered on top.

## Nudges
Computed from stats (streak edge, fastest/slowest app, week-over-week pace), then model- or
template-phrased. Numbers are always real; the model only warms the wording.

## Privacy / docs to update in the SAME release
- Summary quality depends on `historyEnabled` (stats-only mode → summary works off numbers, no content).
  Say so in the enable copy.
- Update the README/brand privacy section: "Insights AI is on-device, default-off, reads only your local
  stats/transcripts, and is cached in `~/.warble/insights-ai.json` (clear/export like the rest)."

## Server change (small, no setup impact)
Add a thin generic **`POST /generate`** to `core/llm-server.py` (no dictation `accept()` guard) for the
structured suggestions/nudges JSON; keep `/clean` purely for dictation. Same venv + model → **no
`setup-cleaner.sh` change**. Summary alone could ride `/clean`; `/generate` is cleaner for JSON.

## Build slices
- **5a — Weekly summary (spine):** `AIInsightsStore` + cache + master switch + summary card + privacy copy.
- **5b — Suggested words:** `pending`-based suggestions first, then model OOV; one-tap accept.
- **5c — Nudges:** computed + phrased chips.
*(Shipping all three in one release per decision; slices are the build order, not separate PRs.)*

## Decisions (locked)
AI cards live **in the Insights tab** (no new sidebar row) · **all three features** ship together ·
generation mode is a **user choice** (auto-refresh / on-demand), default-off master switch · feed the model
**aggregates not raw logs** · suggestions are **deterministic-first**, model-augmented · reuse the existing
**warm MLX server** (the plan's "Ollama/llama.cpp" note is superseded — warble provisions MLX now).

## Risks
- **Small model drift** on the summary → keep the prompt tight, aggregate-driven, low/zero temp; clip with
  `LLMPolish.clip`; on parse/empty failure, fall back to a templated summary (never a broken card).
- **Cold open latency** (server idle-exited) → the "generating…" state + warm re-spawn already cover it.
- **Stats-only mode** → degrade gracefully to numbers-only summary; never imply content we didn't keep.
