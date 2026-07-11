/**
 * Word error rate for the warble benchmarks (scripts/bench/wer-corpus.sh → docs/benchmarks.md):
 * WER = (substitutions + deletions + insertions) / reference words, from a standard word-level
 * Levenshtein alignment. Text is normalized first (lowercase, punctuation stripped, in-word
 * apostrophes kept) so "Hello, world!" scores clean against "hello world". Number formatting is
 * NOT normalized — "3" vs "three" counts as an error, a deliberate strictness documented in
 * docs/benchmarks.md.
 *
 *   bun wer.ts --ref "<text>" --hyp "<text>"   score one pair
 *   bun wer.ts --pairs <file.tsv>              ref<TAB>hyp per line; per-pair lines + pooled total
 */

export function words(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}'\s]+/gu, " ")
    .split(/\s+/)
    .map((w) => w.replace(/^'+|'+$/g, ""))
    .filter((w) => w.length > 0);
}

export interface Score {
  sub: number;
  del: number;
  ins: number;
  n: number; // reference word count
  errors: number;
  wer: number;
}

export function wer(ref: string, hyp: string): Score {
  const r = words(ref);
  const h = words(hyp);
  const R = r.length;
  const H = h.length;
  // dp[i][j] = min edits turning r[0..i) into h[0..j)
  const dp: number[][] = Array.from({ length: R + 1 }, () => new Array<number>(H + 1).fill(0));
  for (let i = 0; i <= R; i++) dp[i][0] = i;
  for (let j = 0; j <= H; j++) dp[0][j] = j;
  for (let i = 1; i <= R; i++) {
    for (let j = 1; j <= H; j++) {
      dp[i][j] = Math.min(
        dp[i - 1][j - 1] + (r[i - 1] === h[j - 1] ? 0 : 1), // match / substitution
        dp[i - 1][j] + 1, // deletion
        dp[i][j - 1] + 1, // insertion
      );
    }
  }
  // Backtrace to split the edit count into S/D/I (tie order can't change the total).
  let i = R;
  let j = H;
  let sub = 0;
  let del = 0;
  let ins = 0;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && dp[i][j] === dp[i - 1][j - 1] + (r[i - 1] === h[j - 1] ? 0 : 1)) {
      if (r[i - 1] !== h[j - 1]) sub++;
      i--;
      j--;
    } else if (i > 0 && dp[i][j] === dp[i - 1][j] + 1) {
      del++;
      i--;
    } else {
      ins++;
      j--;
    }
  }
  const errors = sub + del + ins;
  // Empty reference has no standard WER; call it 0 for an empty hypothesis, 1 otherwise —
  // the corpus never hits it, the guard just keeps the CLI honest.
  const rate = R > 0 ? errors / R : errors > 0 ? 1 : 0;
  return { sub, del, ins, n: R, errors, wer: rate };
}

function fmt(s: Score): string {
  return `wer=${s.wer.toFixed(3)} errors=${s.errors} (S=${s.sub} D=${s.del} I=${s.ins}) N=${s.n}`;
}

if (import.meta.main) {
  const argv = Bun.argv.slice(2);
  const flag = (name: string) => {
    const i = argv.indexOf(name);
    return i >= 0 && i + 1 < argv.length ? argv[i + 1] : undefined;
  };
  const ref = flag("--ref");
  const hyp = flag("--hyp");
  const pairs = flag("--pairs");
  if (ref !== undefined && hyp !== undefined) {
    console.log(fmt(wer(ref, hyp)));
  } else if (pairs !== undefined) {
    const lines = (await Bun.file(pairs).text()).split("\n").filter((l) => l.trim().length > 0);
    let sub = 0;
    let del = 0;
    let ins = 0;
    let n = 0;
    lines.forEach((line, k) => {
      const [r, h = ""] = line.split("\t");
      const s = wer(r, h);
      sub += s.sub;
      del += s.del;
      ins += s.ins;
      n += s.n;
      console.log(`pair=${k + 1} ${fmt(s)}`);
    });
    const errors = sub + del + ins;
    const pooled = n > 0 ? errors / n : errors > 0 ? 1 : 0;
    console.log(`pooled wer=${pooled.toFixed(3)} errors=${errors} (S=${sub} D=${del} I=${ins}) N=${n}`);
  } else {
    console.error('usage: bun wer.ts --ref "<text>" --hyp "<text>" | bun wer.ts --pairs <file.tsv>');
    process.exit(2);
  }
}
