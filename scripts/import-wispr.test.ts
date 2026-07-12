import { afterAll, describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  entriesToCorrections,
  pickDictionaryTable,
  pickHistoryTable,
  planMerge,
  probeTables,
  readEntries,
  readDictionaryFile,
  resolveDictPath,
  resolveWisprDb,
  type Correction,
} from "./import-wispr";

const SCRIPT = join(import.meta.dir, "import-wispr.ts");
const FIXTURE = join(import.meta.dir, "fixtures", "wispr", "flow-sample.sqlite");
const tmpRoots: string[] = [];

function newTmp(): string {
  const d = mkdtempSync(join(tmpdir(), "warble-import-test-"));
  tmpRoots.push(d);
  return d;
}
afterAll(() => { for (const d of tmpRoots) rmSync(d, { recursive: true, force: true }); });

// Build a throwaway Wispr-shaped DB at `path`. `dict` rows are [word, replacement|null].
function buildDb(path: string, opts: { dictTable?: string; dictRows?: [string, string | null][]; withHistory?: boolean } = {}) {
  const db = new Database(path, { create: true });
  const table = opts.dictTable ?? "dictionary";
  db.run(`CREATE TABLE ${table} (id INTEGER PRIMARY KEY, word TEXT, replacement TEXT)`);
  const ins = db.prepare(`INSERT INTO ${table} (word, replacement) VALUES (?, ?)`);
  for (const [w, r] of opts.dictRows ?? [["Myela", null], ["ml", "machine learning"]]) ins.run(w, r);
  if (opts.withHistory) {
    db.run(`CREATE TABLE history (id INTEGER PRIMARY KEY, transcript TEXT)`);
    db.prepare(`INSERT INTO history (transcript) VALUES (?)`).run("hello");
  }
  db.close();
}

// Run the CLI for real (exit codes + env are the point). Returns { code, stdout, stderr }.
function runCli(args: string[], env: Record<string, string> = {}) {
  const p = Bun.spawnSync(["bun", SCRIPT, ...args], {
    env: { ...process.env, ...env },
    stdout: "pipe",
    stderr: "pipe",
  });
  return { code: p.exitCode, stdout: p.stdout.toString(), stderr: p.stderr.toString() };
}

// ---- extraction ----------------------------------------------------------------------------

describe("entriesToCorrections", () => {
  test("a distinctively-cased word becomes a self-casing correction", () => {
    const { corrections } = entriesToCorrections([{ word: "Myela" }]);
    expect(corrections).toEqual([{ from: "myela", to: "Myela", kind: "casing" }]);
  });
  test("a replacement maps from -> to", () => {
    const { corrections } = entriesToCorrections([{ word: "ml", replacement: "machine learning" }]);
    expect(corrections).toEqual([{ from: "ml", to: "machine learning", kind: "replacement" }]);
  });
  test("a replacement that only fixes casing is still kept", () => {
    const { corrections } = entriesToCorrections([{ word: "gpt", replacement: "GPT" }]);
    expect(corrections).toEqual([{ from: "gpt", to: "GPT", kind: "replacement" }]);
  });
  test("an all-lowercase word with no replacement is skipped, not invented", () => {
    const { corrections, skipped } = entriesToCorrections([{ word: "email" }]);
    expect(corrections).toEqual([]);
    expect(skipped.length).toBe(1);
    expect(skipped[0].word).toBe("email");
  });
  test("a redundant replacement identical to the word falls back to casing/skip", () => {
    expect(entriesToCorrections([{ word: "email", replacement: "email" }]).corrections).toEqual([]);
    expect(entriesToCorrections([{ word: "Myela", replacement: "Myela" }]).corrections).toEqual([
      { from: "myela", to: "Myela", kind: "casing" },
    ]);
  });
  test("empty and duplicate rows are ignored", () => {
    const { corrections } = entriesToCorrections([{ word: "  " }, { word: "Myela" }, { word: "myela" }]);
    expect(corrections).toEqual([{ from: "myela", to: "Myela", kind: "casing" }]);
  });
});

// ---- dedupe / merge ------------------------------------------------------------------------

describe("planMerge", () => {
  const incoming: Correction[] = [
    { from: "myela", to: "Myela", kind: "casing" },
    { from: "kokoro", to: "Kokoro", kind: "casing" },
    { from: "ml", to: "machine learning", kind: "replacement" },
  ];
  test("splits into added / already-present / conflicts", () => {
    const plan = planMerge({ kokoro: "Kokoro", myela: "Myela Inc." }, incoming);
    expect(plan.added.map((c) => c.from)).toEqual(["ml"]);
    expect(plan.alreadyPresent.map((c) => c.from)).toEqual(["kokoro"]);
    expect(plan.conflicts).toEqual([{ from: "myela", warble: "Myela Inc.", wispr: "Myela" }]);
  });
  test("an empty warble dictionary imports everything", () => {
    expect(planMerge({}, incoming).added.length).toBe(3);
  });
});

// ---- schema probe --------------------------------------------------------------------------

describe("schema probe", () => {
  test("finds a dictionary table under an unexpected name/columns", () => {
    const d = newTmp();
    const p = join(d, "odd.sqlite");
    const db = new Database(p, { create: true });
    db.run(`CREATE TABLE vocab (id INTEGER PRIMARY KEY, term TEXT, corrected TEXT)`);
    db.close();
    const ro = new Database(p, { readonly: true });
    const pick = pickDictionaryTable(probeTables(ro));
    ro.close();
    expect(pick).toEqual({ table: "vocab", wordCol: "term", replCol: "corrected" });
  });
  test("returns null when no table looks like a dictionary", () => {
    const d = newTmp();
    const p = join(d, "nohit.sqlite");
    const db = new Database(p, { create: true });
    db.run(`CREATE TABLE events (id INTEGER PRIMARY KEY, ts INTEGER, kind TEXT)`);
    db.close();
    const ro = new Database(p, { readonly: true });
    // `kind` is not a word-like column; `events` is not dictionary-like.
    expect(pickDictionaryTable(probeTables(ro))).toBeNull();
    ro.close();
  });
  test("prefers the real dictionary table over a snippets table", () => {
    const d = newTmp();
    const p = join(d, "two.sqlite");
    const db = new Database(p, { create: true });
    db.run(`CREATE TABLE snippets (id INTEGER PRIMARY KEY, trigger TEXT, expansion TEXT)`);
    db.run(`CREATE TABLE dictionary (id INTEGER PRIMARY KEY, word TEXT, replacement TEXT)`);
    db.close();
    const ro = new Database(p, { readonly: true });
    expect(pickDictionaryTable(probeTables(ro))?.table).toBe("dictionary");
    ro.close();
  });
  test("reads rows through the picked table", () => {
    const d = newTmp();
    const p = join(d, "read.sqlite");
    buildDb(p, { dictRows: [["Myela", null], ["ml", "machine learning"]] });
    const ro = new Database(p, { readonly: true });
    const pick = pickDictionaryTable(probeTables(ro))!;
    expect(readEntries(ro, pick)).toEqual([{ word: "Myela" }, { word: "ml", replacement: "machine learning" }]);
    ro.close();
  });
  test("history table is detected for counting", () => {
    const d = newTmp();
    const p = join(d, "hist.sqlite");
    buildDb(p, { withHistory: true });
    const ro = new Database(p, { readonly: true });
    const tables = probeTables(ro);
    expect(pickHistoryTable(tables, "dictionary")).toBe("history");
    ro.close();
  });
});

// ---- path resolution -----------------------------------------------------------------------

describe("path resolution", () => {
  test("WARBLE_DICTIONARY outranks WARBLE_HOME", () => {
    expect(resolveDictPath({ WARBLE_DICTIONARY: "/a/b.json", WARBLE_HOME: "/home" })).toBe("/a/b.json");
  });
  test("WARBLE_HOME points at <home>/dictionary.json", () => {
    expect(resolveDictPath({ WARBLE_HOME: "/store" })).toBe("/store/dictionary.json");
  });
  test("--dict flag wins over everything", () => {
    expect(resolveDictPath({ WARBLE_DICTIONARY: "/a.json" }, "/flag.json")).toBe("/flag.json");
  });
  test("--db flag is honored verbatim", () => {
    expect(resolveWisprDb("/x/y.sqlite")).toBe("/x/y.sqlite");
  });
});

describe("readDictionaryFile", () => {
  test("missing file yields empty maps", () => {
    expect(readDictionaryFile(join(newTmp(), "none.json"))).toEqual({ corrections: {}, pronunciations: {}, pending: {} });
  });
  test("existing corrections and pronunciations survive", () => {
    const p = join(newTmp(), "d.json");
    writeFileSync(p, JSON.stringify({ corrections: { miele: "Myela" }, pronunciations: { myela: "my-ell-uh" } }));
    const d = readDictionaryFile(p);
    expect(d.corrections).toEqual({ miele: "Myela" });
    expect(d.pronunciations).toEqual({ myela: "my-ell-uh" });
  });
});

// ---- CLI end-to-end ------------------------------------------------------------------------

describe("CLI", () => {
  test("dry run reports the plan and writes nothing", () => {
    const home = newTmp();
    const r = runCli(["--db", FIXTURE, "--history"], { WARBLE_HOME: home });
    expect(r.code).toBe(0);
    expect(r.stdout).toContain("new (would import):     6");
    expect(r.stdout).toContain("DRY RUN");
    expect(r.stdout).toContain('table "history" holds 3 entries');
    expect(existsSync(join(home, "dictionary.json"))).toBe(false); // dry run never writes
  });

  test("--write round-trips into a WARBLE_HOME sandbox and merges (not clobbers)", () => {
    const home = newTmp();
    const dictPath = join(home, "dictionary.json");
    // Pre-seed with an existing correction + a conflicting one; both must survive untouched.
    writeFileSync(dictPath, JSON.stringify({
      corrections: { kokoro: "Kokoro", myela: "Myela Inc." },
      pronunciations: { myela: "my-ell-uh" },
    }));
    const r = runCli(["--db", FIXTURE, "--write"], { WARBLE_HOME: home });
    expect(r.code).toBe(0);
    expect(r.stdout).toMatch(/Wrote \d+ new entr/);
    const after = JSON.parse(readFileSync(dictPath, "utf8"));
    // New words imported:
    expect(after.corrections.parakeet).toBe("Parakeet");
    expect(after.corrections.dhaval).toBe("Dhaval");
    expect(after.corrections.ml).toBe("machine learning");
    expect(after.corrections.wisper).toBe("Wispr");
    // Conflict left as-is (warble's value wins), already-present untouched, pronunciations preserved:
    expect(after.corrections.myela).toBe("Myela Inc.");
    expect(after.corrections.kokoro).toBe("Kokoro");
    expect(after.pronunciations.myela).toBe("my-ell-uh");
    // Skipped all-lowercase word never entered the file:
    expect(after.corrections.email).toBeUndefined();
  });

  test("--write to a fresh dictionary creates a native, app-shaped file", () => {
    const home = newTmp();
    const r = runCli(["--db", FIXTURE, "--write"], { WARBLE_HOME: home });
    expect(r.code).toBe(0);
    const obj = JSON.parse(readFileSync(join(home, "dictionary.json"), "utf8"));
    expect(obj).toHaveProperty("_comment");
    expect(obj).toHaveProperty("pronunciations");
    expect(obj).toHaveProperty("pending");
    expect(obj.corrections.myela).toBe("Myela");
  });

  test("a second --write is idempotent (nothing new to write)", () => {
    const home = newTmp();
    runCli(["--db", FIXTURE, "--write"], { WARBLE_HOME: home });
    const before = readFileSync(join(home, "dictionary.json"), "utf8");
    const r = runCli(["--db", FIXTURE, "--write"], { WARBLE_HOME: home });
    expect(r.code).toBe(0);
    expect(r.stdout).toContain("Nothing new to write");
    expect(readFileSync(join(home, "dictionary.json"), "utf8")).toBe(before);
  });

  test("never modifies Wispr's file (size + mtime unchanged after --write)", () => {
    const src = join(newTmp(), "flow.sqlite");
    buildDb(src, { dictRows: [["Myela", null], ["ml", "machine learning"]] });
    const before = statSync(src);
    runCli(["--db", src, "--write"], { WARBLE_HOME: newTmp() });
    const after = statSync(src);
    expect(after.size).toBe(before.size);
    expect(after.mtimeMs).toBe(before.mtimeMs);
  });

  test("missing database exits non-zero with a clear message", () => {
    const r = runCli(["--db", join(newTmp(), "does-not-exist.sqlite")], { WARBLE_HOME: newTmp() });
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("no database at");
  });

  test("a corrupt (non-SQLite) file exits non-zero with a clear message", () => {
    const bad = join(newTmp(), "garbage.sqlite");
    writeFileSync(bad, "this is definitely not a sqlite database\n".repeat(20));
    const r = runCli(["--db", bad], { WARBLE_HOME: newTmp() });
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("not a readable SQLite database");
  });

  test("a database with no dictionary-like table exits non-zero and reports what it saw", () => {
    const p = join(newTmp(), "empty.sqlite");
    const db = new Database(p, { create: true });
    db.run(`CREATE TABLE events (id INTEGER PRIMARY KEY, ts INTEGER)`);
    db.close();
    const r = runCli(["--db", p], { WARBLE_HOME: newTmp() });
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("no dictionary-like table found");
    expect(r.stderr).toContain("events");
  });

  test("--help exits 0 with usage", () => {
    const r = runCli(["--help"]);
    expect(r.code).toBe(0);
    expect(r.stdout).toContain("usage:");
  });

  test("an unknown flag exits 2", () => {
    const r = runCli(["--nope"]);
    expect(r.code).toBe(2);
    expect(r.stderr).toContain("unknown argument");
  });
});
