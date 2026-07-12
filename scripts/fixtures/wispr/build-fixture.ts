#!/usr/bin/env bun
// Builds the committed synthetic Wispr Flow database used by the import tests + the regression
// check. This is NOT real Wispr data — it's a plausible reconstruction of the shape the April 2026
// forensic teardown described (a dictionary table + a history table), used only so the tests are
// deterministic on any machine. Re-run to regenerate:
//
//   bun scripts/fixtures/wispr/build-fixture.ts
//
// Kept a few KB and committed so `regression.sh` needs no build step.

import { Database } from "bun:sqlite";
import { existsSync, rmSync } from "node:fs";
import { join } from "node:path";

const OUT = join(import.meta.dir, "flow-sample.sqlite");

if (existsSync(OUT)) rmSync(OUT);
const db = new Database(OUT, { create: true });

// A dictionary table with a distinctive casing set (the common case: auto-learned proper nouns) and
// a couple of real replacements — plus one all-lowercase word that has nothing to correct.
db.run(`CREATE TABLE dictionary (
  id INTEGER PRIMARY KEY,
  word TEXT NOT NULL,
  replacement TEXT,
  starred INTEGER DEFAULT 0,
  created_at TEXT
)`);
const dictRows: [string, string | null, number][] = [
  ["Myela", null, 1],          // casing: myela -> Myela
  ["Parakeet", null, 0],       // casing: parakeet -> Parakeet
  ["Kokoro", null, 1],         // casing: kokoro -> Kokoro (test seeds this as already-present)
  ["Dhaval", null, 0],         // casing: dhaval -> Dhaval
  ["ml", "machine learning", 0], // replacement: ml -> machine learning
  ["wisper", "Wispr", 0],      // replacement (misspelling fix): wisper -> Wispr
  ["email", null, 0],          // skipped: all-lowercase, no replacement
];
const ins = db.prepare("INSERT INTO dictionary (word, replacement, starred, created_at) VALUES (?, ?, ?, ?)");
for (const [w, r, s] of dictRows) ins.run(w, r, s, "2026-05-01T12:00:00Z");

// A history table so --history has something to count. Its text is never read by the import tool;
// the contents here exist only to prove the count path.
db.run(`CREATE TABLE history (
  id INTEGER PRIMARY KEY,
  transcript TEXT,
  app TEXT,
  created_at TEXT
)`);
const h = db.prepare("INSERT INTO history (transcript, app, created_at) VALUES (?, ?, ?)");
h.run("meet friday at four", "Slack", "2026-05-01T09:00:00Z");
h.run("ship the myela engine", "Terminal", "2026-05-01T09:05:00Z");
h.run("read it back to me", "Mail", "2026-05-01T09:10:00Z");

// A snippets table too — proves the probe prefers the real "dictionary" table over this one.
db.run(`CREATE TABLE snippets (id INTEGER PRIMARY KEY, trigger TEXT, expansion TEXT)`);
db.prepare("INSERT INTO snippets (trigger, expansion) VALUES (?, ?)").run("sign off", "Best,\nSeth");

db.close();
process.stdout.write(`wrote ${OUT}\n`);
