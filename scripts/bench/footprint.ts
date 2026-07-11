/**
 * Idle-footprint sampler (docs/benchmarks.md §3): RSS + CPU for warble.app and its warm servers,
 * sampled from `ps` over a window. CPU is Δcputime / Δwalltime across the WHOLE window — the
 * honest idle number — not ps's decaying %cpu average. Run it twice (servers warm, then servers
 * off) for the on-vs-off table; the sampler only observes, it never starts or stops anything.
 *
 *   bun footprint.ts [--minutes 3] [--interval 5]
 *   bun footprint.ts --smoke     two 1s samples + a row for its own pid, so the ps parsing is
 *                                provable on any machine even with warble not running
 */

interface Group {
  name: string;
  match: (pid: number, command: string) => boolean;
}

const groups: Group[] = [
  {
    name: "warble (app)",
    match: (_, c) => /warble\.app\/Contents\/MacOS\/warble|\.build\/(debug|release)\/warble/.test(c),
  },
  { name: "ASR server (Parakeet)", match: (_, c) => /asr-server\.py/.test(c) },
  { name: "LLM server (MLX polish)", match: (_, c) => /llm-server\.py/.test(c) },
  { name: "TTS server (Kokoro)", match: (_, c) => /say-server\.ts/.test(c) },
];

const argv = Bun.argv.slice(2);
const smoke = argv.includes("--smoke");
const flag = (name: string, dflt: number) => {
  const i = argv.indexOf(name);
  const v = i >= 0 && i + 1 < argv.length ? Number(argv[i + 1]) : NaN;
  return Number.isFinite(v) && v > 0 ? v : dflt;
};
const intervalSecs = smoke ? 1 : flag("--interval", 5);
const samples = smoke ? 2 : Math.max(2, Math.round((flag("--minutes", 3) * 60) / intervalSecs));

if (smoke) {
  groups.push({ name: "sampler (self — smoke only)", match: (pid) => pid === process.pid });
}

/** ps TIME → seconds. Forms seen on macOS: "0:02.97", "26:14.52", "1:02:03", "2-01:02:03". */
function cpuSeconds(t: string): number {
  const [days, rest] = t.includes("-") ? t.split("-") : ["0", t];
  return t
    ? rest.split(":").reduce((acc, p) => acc * 60 + Number(p), 0) + Number(days) * 86400
    : 0;
}

interface Proc {
  pid: number;
  rssKB: number;
  cpuSecs: number;
  command: string;
}

function sample(): Proc[] {
  const out = Bun.spawnSync(["ps", "axo", "pid=,rss=,cputime=,command="]).stdout.toString();
  const procs: Proc[] = [];
  for (const line of out.split("\n")) {
    const m = line.match(/^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$/);
    if (!m) continue;
    procs.push({ pid: Number(m[1]), rssKB: Number(m[2]), cpuSecs: cpuSeconds(m[3]), command: m[4] });
  }
  return procs;
}

// Per group: RSS of matching pids summed per tick (avg/max over ticks seen), and per-pid
// first/last cputime so CPU% is a delta over the window, robust to pids coming and going.
const rssPerTick = new Map<string, number[]>();
const cpuSpan = new Map<string, Map<number, { first: number; last: number }>>();
for (const g of groups) {
  rssPerTick.set(g.name, []);
  cpuSpan.set(g.name, new Map());
}

const t0 = Date.now();
for (let tick = 0; tick < samples; tick++) {
  if (tick > 0) await Bun.sleep(intervalSecs * 1000);
  const procs = sample();
  if (procs.length === 0) {
    console.error("footprint.ts: ps returned nothing parseable");
    process.exit(1);
  }
  for (const g of groups) {
    const mine = procs.filter((p) => g.match(p.pid, p.command));
    if (mine.length === 0) continue;
    rssPerTick.get(g.name)!.push(mine.reduce((a, p) => a + p.rssKB, 0));
    const span = cpuSpan.get(g.name)!;
    for (const p of mine) {
      const s = span.get(p.pid);
      if (s) s.last = p.cpuSecs;
      else span.set(p.pid, { first: p.cpuSecs, last: p.cpuSecs });
    }
  }
}
const elapsedSecs = (Date.now() - t0) / 1000;

const mb = (kb: number) => `${(kb / 1024).toFixed(1)} MB`;
const pad = (s: string, w: number) => s.padEnd(w);
console.log(`footprint: ${samples} samples over ${elapsedSecs.toFixed(0)}s (interval ${intervalSecs}s)`);
console.log(`${pad("process", 28)}${pad("pids", 6)}${pad("rss avg", 12)}${pad("rss max", 12)}cpu avg`);

let totalRss = 0;
let totalCpu = 0;
let selfRssOK = true;
for (const g of groups) {
  const rss = rssPerTick.get(g.name)!;
  const span = cpuSpan.get(g.name)!;
  if (rss.length === 0) {
    console.log(`${pad(g.name, 28)}${pad("—", 6)}not running`);
    continue;
  }
  const avg = rss.reduce((a, b) => a + b, 0) / rss.length;
  const max = Math.max(...rss);
  const cpuDelta = [...span.values()].reduce((a, s) => a + (s.last - s.first), 0);
  const cpuPct = (cpuDelta / elapsedSecs) * 100;
  totalRss += avg;
  totalCpu += cpuPct;
  if (g.name.startsWith("sampler") && avg === 0) selfRssOK = false;
  console.log(`${pad(g.name, 28)}${pad(String(span.size), 6)}${pad(mb(avg), 12)}${pad(mb(max), 12)}${cpuPct.toFixed(2)}%`);
}
console.log(`${pad("total (running)", 34)}${pad(mb(totalRss), 12)}${pad("", 12)}${totalCpu.toFixed(2)}%`);

if (smoke && !selfRssOK) {
  console.error("footprint.ts: smoke self-check failed (own RSS parsed as 0)");
  process.exit(1);
}
