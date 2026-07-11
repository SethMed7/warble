/**
 * Median/p95 over numbers on stdin, one per line — aggregates latency.sh's cold mode, where
 * every run is its own process and prints a single ms value. Conventions deliberately match
 * the summary `--bench-e2e` prints in-process: median = midpoint average for even n; p95 =
 * nearest-rank (ceil(0.95·n)).
 *
 *   printf '12\n10\n14\n' | bun stats.ts
 */

export function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m] : (s[m - 1] + s[m]) / 2;
}

export function p95(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil(0.95 * s.length) - 1)];
}

if (import.meta.main) {
  const text = await new Response(Bun.stdin.stream()).text();
  const xs = text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
    .map(Number)
    .filter((x) => Number.isFinite(x));
  if (xs.length === 0) {
    console.error("stats.ts: no numbers on stdin");
    process.exit(1);
  }
  const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
  console.log(
    `n=${xs.length} median=${median(xs).toFixed(1)} p95=${p95(xs).toFixed(1)} ` +
      `min=${Math.min(...xs).toFixed(1)} max=${Math.max(...xs).toFixed(1)} mean=${mean.toFixed(1)}`,
  );
}
