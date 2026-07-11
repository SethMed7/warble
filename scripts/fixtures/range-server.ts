// Loopback Range-request fixture server for scripts/regression.sh (the setup-resume check).
// Serves ONE fixture file with honest HTTP semantics — HEAD, GET, and `Range: bytes=N-`
// (206 + Content-Range) — plus a /noresume/ path prefix that deliberately ignores Range and
// sends the whole file (200): the misbehaving-server case ResumableFetch must restart on.
// Binds 127.0.0.1 on an ephemeral port (printed as "port NNNN") and appends one line per
// request to the log file: "<METHOD> <range-header-or-->". Loopback only, by regression law:
// the suite makes no external network calls.
//
//   bun scripts/fixtures/range-server.ts <fixture-file> <request-log>

import { appendFileSync } from "node:fs";

const [file, logPath] = process.argv.slice(2);
if (!file || !logPath) {
  console.error("usage: bun range-server.ts <fixture-file> <request-log>");
  process.exit(2);
}
const bytes = new Uint8Array(await Bun.file(file).arrayBuffer());

const server = Bun.serve({
  hostname: "127.0.0.1",
  port: 0,
  fetch(req) {
    const range = req.headers.get("range") ?? "-";
    appendFileSync(logPath, `${req.method} ${range}\n`);
    if (req.method === "HEAD") {
      return new Response(null, {
        headers: { "content-length": String(bytes.length), "accept-ranges": "bytes" },
      });
    }
    const noresume = new URL(req.url).pathname.startsWith("/noresume/");
    const m = noresume ? null : /^bytes=(\d+)-$/.exec(range);
    if (m) {
      const start = Number(m[1]);
      if (start >= bytes.length) {
        return new Response(null, {
          status: 416,
          headers: { "content-range": `bytes */${bytes.length}` },
        });
      }
      return new Response(bytes.slice(start), {
        status: 206,
        headers: {
          "content-range": `bytes ${start}-${bytes.length - 1}/${bytes.length}`,
          "content-length": String(bytes.length - start),
        },
      });
    }
    return new Response(bytes, { headers: { "content-length": String(bytes.length) } });
  },
});

console.log(`port ${server.port}`);
