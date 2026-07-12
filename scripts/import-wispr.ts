#!/usr/bin/env bun
// import-wispr.ts — the concrete switch path for someone leaving Wispr Flow.
//
// WHAT THIS DOES, PLAINLY: it reads Wispr Flow's LOCAL database — the SQLite file already sitting
// on your own Mac under ~/Library/Application Support/Wispr Flow/ — extracts your custom-dictionary
// words (and their replacements, if any), and merges them into warble's dictionary. That is the
// whole story: this has NOTHING to do with Wispr's servers, your Wispr account, or the network.
// The database is opened READ-ONLY; the original file is never modified. Nothing leaves the machine.
//
// Wispr's on-disk schema is undocumented and may change between versions. Rather than assume table
// or column names, this tool PROBES the database (via sqlite_master), finds the dictionary-like
// table by name/column heuristics, and REPORTS exactly what it found. If it can't find one, it
// says so and exits non-zero instead of guessing silently.
//
// DRY RUN BY DEFAULT: prints what it would import and changes nothing. Pass --write to actually
// merge into warble's dictionary file. Existing warble entries are never overwritten (conflicts are
// reported and left as-is); already-present entries are skipped.
//
//   bun scripts/import-wispr.ts                 # dry run against the default Wispr location
//   bun scripts/import-wispr.ts --write         # merge new dictionary entries into warble
//   bun scripts/import-wispr.ts --db <path>     # point at a specific .db (e.g. a backup)
//   bun scripts/import-wispr.ts --history       # also report (count only) how much history exists
//   bun scripts/import-wispr.ts --dict <path>   # write to a specific warble dictionary file
//
// bun:sqlite is built into bun — no dependencies added.

import { Database } from "bun:sqlite";
import { existsSync, readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";

// ---- types ---------------------------------------------------------------------------------

export interface TableInfo { name: string; columns: string[]; }
export interface DictPick { table: string; wordCol: string; replCol?: string; }
export interface RawEntry { word: string; replacement?: string; }
export interface Correction { from: string; to: string; kind: "replacement" | "casing"; }
export interface Skipped { word: string; reason: string; }
export interface WarbleDict {
  _comment?: string;
  corrections: Record<string, string>;
  pronunciations: Record<string, string>;
  pending: Record<string, unknown>;
  [k: string]: unknown;
}
export interface MergePlan {
  added: Correction[];
  alreadyPresent: Correction[];
  conflicts: { from: string; warble: string; wispr: string }[];
}

// The self-documenting comment warble's Lexicon.swift writes; kept verbatim so a file this tool
// creates fresh reads identically to one the app made.
const LEXICON_COMMENT =
  'corrections: map a misspelling (lowercase) to the spelling you want — e.g. "myayla": "Myela"; ' +
  "warble applies these to every dictation. pronunciations: map a word (lowercase) to how read-aloud " +
  'should say it — e.g. "myela": "my-ell-uh".';

// Wispr Flow's per-user data folder on macOS (its own docs point users here to delete the local DB).
export const WISPR_DIR = join(homedir(), "Library", "Application Support", "Wispr Flow");
// The database filename documented by the April 2026 forensic teardown (wensenwu.com). If it isn't
// there under this name, we probe the folder for any *.sqlite / *.db instead — the name may change.
export const WISPR_DB = join(WISPR_DIR, "flow.sqlite");

// ---- path resolution -----------------------------------------------------------------------

// Where warble reads its dictionary from — mirrors Lexicon.fileURL precedence, plus the WARBLE_HOME
// store-relocation seam the app's other stores honor (Snippets/InsightStore), so import writes
// exactly where the running app will read.
export function resolveDictPath(env: Record<string, string | undefined>, flagDict?: string): string {
  if (flagDict) return expandTilde(flagDict);
  for (const key of ["WARBLE_DICTIONARY", "DICTADO_DICTIONARY"]) {
    const v = env[key];
    if (v && v.length) return expandTilde(v);
  }
  if (env.WARBLE_HOME && env.WARBLE_HOME.length) return join(env.WARBLE_HOME, "dictionary.json");
  return join(homedir(), ".warble", "dictionary.json");
}

// The Wispr DB to read: an explicit --db wins; else the documented default; else the first
// *.sqlite/*.db in Wispr's folder (schema/name may drift). Returns null if nothing is found.
export function resolveWisprDb(flagDb?: string): string | null {
  if (flagDb) return expandTilde(flagDb);
  if (existsSync(WISPR_DB)) return WISPR_DB;
  if (existsSync(WISPR_DIR)) {
    const cand = readdirSync(WISPR_DIR)
      .filter((f) => /\.(sqlite3?|db)$/i.test(f))
      .sort();
    if (cand.length) return join(WISPR_DIR, cand[0]);
  }
  return null;
}

function expandTilde(p: string): string {
  if (p === "~") return homedir();
  if (p.startsWith("~/")) return join(homedir(), p.slice(2));
  return p;
}

// ---- read-only open ------------------------------------------------------------------------

export class ImportError extends Error {}

// Open Wispr's DB read-only. The original file is never modified and — true to warble's own thesis
// — never copied aside either: if the read-only open fails because Wispr is running (its database is
// WAL-locked), we tell the user to quit Wispr rather than silently hoarding a multi-hundred-MB copy
// of their data in temp. Quitting Wispr releases the lock (this is also Wispr's own documented step
// before touching the local DB), after which a plain read-only open works.
export function openWisprReadOnly(path: string): Database {
  if (!existsSync(path)) {
    throw new ImportError(
      `no database at ${path}\n` +
        `  If Wispr Flow is installed, its DB usually lives at:\n    ${WISPR_DB}\n` +
        `  Point at it (or a backup) with --db <path>.`,
    );
  }
  try {
    const db = new Database(path, { readonly: true });
    db.query("SELECT name FROM sqlite_master LIMIT 1").all(); // force a real read to surface corruption
    return db;
  } catch (e) {
    const msg = String((e as Error).message || e);
    if (/not a database|file is encrypted|malformed|corrupt/i.test(msg)) {
      throw new ImportError(`${path} is not a readable SQLite database (${msg.trim()}).`);
    }
    throw new ImportError(
      `could not open ${path} read-only (${msg.trim()}).\n` +
        `  If Wispr Flow is running, quit it and try again — warble won't copy your database aside to\n` +
        `  work around a lock. (Quitting Wispr is its own documented step before touching the local DB.)`,
    );
  }
}

// ---- schema probe --------------------------------------------------------------------------

export function probeTables(db: Database): TableInfo[] {
  const rows = db
    .query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    .all() as { name: string }[];
  return rows.map((r) => ({ name: r.name, columns: tableColumns(db, r.name) }));
}

function tableColumns(db: Database, table: string): string[] {
  // Table names come from sqlite_master (the user's own DB); still quote-escape defensively.
  const safe = '"' + table.replace(/"/g, '""') + '"';
  const info = db.query(`PRAGMA table_info(${safe})`).all() as { name: string }[];
  return info.map((c) => c.name);
}

// Column-name heuristics. Exact matches win over "contains" matches; a word column is required for a
// table to count as a dictionary, a replacement column is optional.
const WORD_EXACT = ["word", "term", "phrase", "spoken", "trigger", "original", "from", "key", "text", "entry", "token", "spelling_from"];
const WORD_CONTAINS = ["word", "term", "phrase", "trigger", "token"];
const REPL_EXACT = ["replacement", "replace", "corrected", "correction", "spelling", "to", "value", "expansion", "output", "substitution", "result", "target", "spelling_to"];
const REPL_CONTAINS = ["replac", "correct", "expansion", "substitut"];

function pickColumn(columns: string[], exact: string[], contains: string[], exclude?: string): string | undefined {
  const lc = columns.map((c) => ({ raw: c, lc: c.toLowerCase() }));
  for (const name of exact) {
    const hit = lc.find((c) => c.lc === name && c.raw !== exclude);
    if (hit) return hit.raw;
  }
  for (const c of lc) {
    if (c.raw === exclude) continue;
    if (contains.some((frag) => c.lc.includes(frag))) return c.raw;
  }
  return undefined;
}

// Choose the most dictionary-like table. Returns null when nothing qualifies (unexpected schema).
export function pickDictionaryTable(tables: TableInfo[]): DictPick | null {
  let best: { pick: DictPick; score: number } | null = null;
  for (const t of tables) {
    const wordCol = pickColumn(t.columns, WORD_EXACT, WORD_CONTAINS);
    if (!wordCol) continue;
    const replCol = pickColumn(t.columns, REPL_EXACT, REPL_CONTAINS, wordCol);
    let score = 0;
    if (/dict|lexicon|vocab|glossar/i.test(t.name)) score += 3;
    if (/word|term/i.test(t.name)) score += 1;
    if (replCol) score += 1;
    const pick: DictPick = { table: t.name, wordCol, ...(replCol ? { replCol } : {}) };
    if (!best || score > best.score) best = { pick, score };
  }
  return best ? best.pick : null;
}

// A history-like table (for the --history count only — its text is never read or imported).
export function pickHistoryTable(tables: TableInfo[], exclude?: string): string | null {
  for (const t of tables) {
    if (t.name === exclude) continue;
    if (/histor|dictation|transcript|session/i.test(t.name)) return t.name;
    if (t.columns.some((c) => /transcript|dictation|asr_text|content/i.test(c))) return t.name;
  }
  return null;
}

export function countRows(db: Database, table: string): number {
  const safe = '"' + table.replace(/"/g, '""') + '"';
  const row = db.query(`SELECT COUNT(*) AS n FROM ${safe}`).get() as { n: number };
  return row?.n ?? 0;
}

// ---- extraction ----------------------------------------------------------------------------

export function readEntries(db: Database, pick: DictPick): RawEntry[] {
  const safe = '"' + pick.table.replace(/"/g, '""') + '"';
  const rows = db.query(`SELECT * FROM ${safe}`).all() as Record<string, unknown>[];
  const out: RawEntry[] = [];
  for (const r of rows) {
    const word = str(r[pick.wordCol]);
    if (!word) continue;
    const replacement = pick.replCol ? str(r[pick.replCol]) : "";
    out.push(replacement ? { word, replacement } : { word });
  }
  return out;
}

function str(v: unknown): string {
  if (v === null || v === undefined) return "";
  return String(v).trim();
}

// Map Wispr entries onto warble's correction model (lowercased "from" -> verbatim "to"). A
// replacement gives the target; a bare word with distinctive casing becomes a self-casing fix (the
// canonical "myela" -> "Myela"). A bare all-lowercase word has nothing to correct toward, so it's
// reported as skipped rather than invented.
export function entriesToCorrections(entries: RawEntry[]): { corrections: Correction[]; skipped: Skipped[] } {
  const corrections: Correction[] = [];
  const skipped: Skipped[] = [];
  const seen = new Set<string>();
  for (const e of entries) {
    const word = e.word.trim();
    if (!word) continue;
    const repl = (e.replacement ?? "").trim();
    const hasRepl = repl.length > 0 && repl !== word; // a replacement that differs (in content or casing)
    const to = hasRepl ? repl : word;
    const from = word.toLowerCase();
    if (from === to) {
      skipped.push({ word, reason: "all-lowercase word with no replacement — nothing to correct toward" });
      continue;
    }
    if (seen.has(from)) continue; // first spelling wins within one import
    seen.add(from);
    corrections.push({ from, to, kind: hasRepl ? "replacement" : "casing" });
  }
  return { corrections, skipped };
}

// ---- merge ---------------------------------------------------------------------------------

export function planMerge(existing: Record<string, string>, incoming: Correction[]): MergePlan {
  const added: Correction[] = [];
  const alreadyPresent: Correction[] = [];
  const conflicts: { from: string; warble: string; wispr: string }[] = [];
  for (const c of incoming) {
    if (!(c.from in existing)) {
      added.push(c);
    } else if (existing[c.from] === c.to) {
      alreadyPresent.push(c);
    } else {
      conflicts.push({ from: c.from, warble: existing[c.from], wispr: c.to });
    }
  }
  return { added, alreadyPresent, conflicts };
}

// ---- warble dictionary file I/O ------------------------------------------------------------

export function readDictionaryFile(path: string): WarbleDict {
  const base: WarbleDict = { corrections: {}, pronunciations: {}, pending: {} };
  if (!existsSync(path)) return base;
  try {
    const obj = JSON.parse(readFileSync(path, "utf8"));
    if (obj && typeof obj === "object") {
      return {
        ...obj,
        corrections: isStrMap(obj.corrections) ? obj.corrections : {},
        pronunciations: isStrMap(obj.pronunciations) ? obj.pronunciations : {},
        pending: obj.pending && typeof obj.pending === "object" ? obj.pending : {},
      };
    }
  } catch {
    // A malformed dictionary is a real error — don't clobber it silently.
    throw new ImportError(`warble dictionary at ${path} is not valid JSON; refusing to overwrite it.`);
  }
  return base;
}

function isStrMap(v: unknown): v is Record<string, string> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

export function writeDictionaryFile(path: string, dict: WarbleDict): void {
  mkdirSync(dirname(path), { recursive: true });
  const out: WarbleDict = {
    _comment: dict._comment ?? LEXICON_COMMENT,
    corrections: dict.corrections,
    pronunciations: dict.pronunciations,
    pending: dict.pending,
  };
  for (const k of Object.keys(dict)) if (!(k in out)) out[k] = dict[k]; // preserve any extra keys
  writeFileSync(path, sortedJson(out) + "\n");
}

// Match Lexicon.save's sorted-keys + pretty output so files this tool and the app write are stable.
function sortedJson(value: unknown): string {
  return JSON.stringify(value, sortKeysReplacer(), 2);
}
function sortKeysReplacer() {
  return function (this: unknown, _key: string, val: unknown) {
    if (val && typeof val === "object" && !Array.isArray(val)) {
      const sorted: Record<string, unknown> = {};
      for (const k of Object.keys(val as Record<string, unknown>).sort()) sorted[k] = (val as Record<string, unknown>)[k];
      return sorted;
    }
    return val;
  };
}

// ---- CLI -----------------------------------------------------------------------------------

interface Args { db?: string; dict?: string; write: boolean; history: boolean; help: boolean; }

export function parseArgs(argv: string[]): Args {
  const a: Args = { write: false, history: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--write": a.write = true; break;
      case "--history": a.history = true; break;
      case "-h": case "--help": a.help = true; break;
      case "--db": a.db = argv[++i]; break;
      case "--dict": a.dict = argv[++i]; break;
      default:
        throw new ImportError(`unknown argument: ${arg}\n${USAGE}`);
    }
  }
  if ((a.db !== undefined && !a.db) || (a.dict !== undefined && !a.dict)) {
    throw new ImportError(`--db and --dict require a path\n${USAGE}`);
  }
  return a;
}

const USAGE = `usage: bun scripts/import-wispr.ts [--db <path>] [--dict <path>] [--write] [--history]

  Reads Wispr Flow's LOCAL dictionary (SQLite, on this Mac, read-only) and merges the custom words
  into warble's dictionary. Dry run by default — pass --write to commit. Nothing is sent anywhere.`;

function main(argv: string[]): number {
  let args: Args;
  try {
    args = parseArgs(argv);
  } catch (e) {
    process.stderr.write((e as Error).message + "\n");
    return 2;
  }
  if (args.help) {
    process.stdout.write(USAGE + "\n");
    return 0;
  }

  const dbPath = resolveWisprDb(args.db);
  const dictPath = resolveDictPath(process.env, args.dict);

  process.stdout.write("warble — import your Wispr Flow dictionary\n");
  process.stdout.write(
    "Reads Wispr's LOCAL database on this Mac, opened read-only. Nothing is sent anywhere and this\n" +
      "has nothing to do with Wispr's servers or your account. Wispr's schema is undocumented and may\n" +
      "change, so this tool probes the database and reports what it found rather than assuming.\n\n",
  );

  if (!dbPath) {
    process.stderr.write(
      `Could not find a Wispr Flow database.\n` +
        `  Looked for: ${WISPR_DB}\n` +
        `  If Wispr is installed elsewhere or the file has a different name, pass --db <path>.\n`,
    );
    return 1;
  }

  let db: Database;
  try {
    db = openWisprReadOnly(dbPath);
  } catch (e) {
    process.stderr.write((e as Error).message + "\n");
    return 1;
  }

  try {
    const tables = probeTables(db);
    const pick = pickDictionaryTable(tables);

    process.stdout.write(`Source (read-only): ${dbPath}\n`);
    process.stdout.write(`warble dictionary:  ${dictPath}\n\n`);

    if (!pick) {
      process.stderr.write(
        `Schema probe: no dictionary-like table found in this database.\n` +
          `  Tables seen:\n` +
          tables.map((t) => `    ${t.name} (${t.columns.join(", ")})`).join("\n") +
          `\n  Nothing was imported. If Wispr changed its schema, please open an issue with the table\n` +
          `  list above so the heuristics can be updated.\n`,
      );
      return 1;
    }

    process.stdout.write(
      `Schema probe: reading table "${pick.table}" ` +
        `(word column "${pick.wordCol}"${pick.replCol ? `, replacement column "${pick.replCol}"` : ", no replacement column"}).\n\n`,
    );

    const entries = readEntries(db, pick);
    const { corrections, skipped } = entriesToCorrections(entries);
    const existing = readDictionaryFile(dictPath);
    const plan = planMerge(existing.corrections, corrections);

    process.stdout.write(`Custom-dictionary entries found: ${entries.length}\n`);
    process.stdout.write(`  new (would import):     ${plan.added.length}\n`);
    process.stdout.write(`  already in warble:      ${plan.alreadyPresent.length}\n`);
    process.stdout.write(`  conflicts (kept as-is): ${plan.conflicts.length}\n`);
    process.stdout.write(`  skipped (no correction): ${skipped.length}\n\n`);

    if (plan.added.length) {
      process.stdout.write("New entries:\n");
      for (const c of plan.added) process.stdout.write(`  "${c.from}" -> "${c.to}"  (${c.kind})\n`);
      process.stdout.write("\n");
    }
    if (plan.conflicts.length) {
      process.stdout.write("Conflicts — warble already maps these to something else, left unchanged:\n");
      for (const c of plan.conflicts) process.stdout.write(`  "${c.from}": warble has "${c.warble}", Wispr has "${c.wispr}"\n`);
      process.stdout.write("\n");
    }
    if (skipped.length) {
      process.stdout.write("Skipped:\n");
      for (const s of skipped) process.stdout.write(`  "${s.word}" — ${s.reason}\n`);
      process.stdout.write("\n");
    }

    if (args.history) {
      const histTable = pickHistoryTable(tables, pick.table);
      if (histTable) {
        const n = countRows(db, histTable);
        process.stdout.write(
          `History: table "${histTable}" holds ${n} entr${n === 1 ? "y" : "ies"} (count only).\n` +
            `  warble does not import Wispr's history text in this version — dictionary only.\n\n`,
        );
      } else {
        process.stdout.write("History: no history-like table found.\n\n");
      }
    }

    if (args.write) {
      if (plan.added.length === 0) {
        process.stdout.write("Nothing new to write — warble's dictionary already covers these.\n");
        return 0;
      }
      const merged: WarbleDict = { ...existing, corrections: { ...existing.corrections } };
      for (const c of plan.added) merged.corrections[c.from] = c.to;
      writeDictionaryFile(dictPath, merged);
      process.stdout.write(`Wrote ${plan.added.length} new entr${plan.added.length === 1 ? "y" : "ies"} to ${dictPath}\n`);
    } else {
      process.stdout.write(
        plan.added.length
          ? `DRY RUN — nothing was written. Re-run with --write to merge the ${plan.added.length} new entr${plan.added.length === 1 ? "y" : "ies"}.\n`
          : "DRY RUN — nothing new to import; warble's dictionary already covers these.\n",
      );
    }
    return 0;
  } finally {
    db.close();
  }
}

if (import.meta.main) {
  process.exit(main(process.argv.slice(2)));
}
