#!/usr/bin/env python3
"""warble's warm LLM polish server — loads a small on-device instruct model via MLX (Apple's Metal
array framework) ONCE and serves dictation cleanup over local HTTP, so the polish step is never
slowed by the per-clip model reload a one-shot CLI pays. Warm polishes are ~0.3-1s. Same warm-server
pattern as core/asr-server.py. 100% on-device; binds 127.0.0.1 ONLY; reaches the network NEVER at
request time (the app spawns it with HF_HUB_OFFLINE=1, so the weights downloaded with your consent at
setup are the only ones used). Installed + run by scripts/setup-cleaner.sh (a venv with mlx-lm).
Apple Silicon only.

Protocol (loopback, same machine):
  GET  /health                                                         -> 200 {"ok": true}
  POST /clean     {"system": "...", "text": "...", "max_tokens": 1024}  -> 200 {"text": "..."}
  POST /generate  {"system": "...", "text": "...", "max_tokens": 256}   -> 200 {"text": "..."}
"""
import os, json, time, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import mlx.core as mx
from mlx_lm import load, generate


def env(*names, default=""):
    for n in names:
        v = os.environ.get(n)
        if v:
            return v
    return default


MODEL = env("WARBLE_LLM_MODEL", default=env("VOZ_LLM_MODEL", default="mlx-community/Qwen2.5-1.5B-Instruct-4bit"))  # VOZ_: rename-era fallback
PORT = int(env("WARBLE_LLM_PORT", default="8766"))

# Load once. On a fresh machine the weights must already be in the Hugging Face cache (setup-cleaner.sh
# downloaded them with your consent); HF_HUB_OFFLINE=1 (set by the app) guarantees no network here.
model, tokenizer = load(MODEL)


# Reclaim memory when unused: exit after a stretch with no requests (the app re-warms on the next
# dictation). Also reclaims an orphaned server left behind by a crash/force-quit.
IDLE = float(env("WARBLE_LLM_IDLE_S", default="600"))
_last = [time.time()]


def _idle_watch():
    while True:
        time.sleep(30)
        if time.time() - _last[0] > IDLE:
            os._exit(0)


threading.Thread(target=_idle_watch, daemon=True).start()


def polish(system, text, max_tokens):
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": text})
    prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
    # Greedy (temp 0) for determinism. mlx-lm's generate() signature has drifted across versions, so
    # try the current sampler API, then the older temp kwarg, then the bare positional form.
    try:
        from mlx_lm.sample_utils import make_sampler
        return generate(model, tokenizer, prompt=prompt, max_tokens=max_tokens,
                        sampler=make_sampler(temp=0.0), verbose=False)
    except TypeError:
        pass
    try:
        return generate(model, tokenizer, prompt=prompt, max_tokens=max_tokens, temp=0.0, verbose=False)
    except TypeError:
        return generate(model, tokenizer, prompt, max_tokens=max_tokens)


def release_cache():
    """Drop MLX's Metal buffer cache after each generation so idle RSS shrinks back toward the loaded
    weights (the cache holds hundreds of MB and MLX never returns it on its own). The API name has
    drifted across MLX versions; a failed clear must never fail the request."""
    try:
        mx.clear_cache()
    except AttributeError:
        try:
            mx.metal.clear_cache()
        except Exception:
            pass
    except Exception:
        pass


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"ok": True})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        # /generate is a sibling of /clean — same generic system+text->text behavior (the Insights AI
        # summary phrases aggregate numbers); both run the same generation function.
        if self.path not in ("/clean", "/generate"):
            self._send(404, {"error": "not found"})
            return
        _last[0] = time.time()
        try:
            n = int(self.headers.get("Content-Length", 0))
            req = json.loads(self.rfile.read(n) or b"{}")
            text = (req.get("text") or "").strip()
            if not text:
                self._send(200, {"text": ""})
                return
            out = polish(req.get("system") or "", text, int(req.get("max_tokens") or 1024))
            release_cache()
            self._send(200, {"text": (out or "").strip()})
        except Exception as e:  # any failure -> the app falls back to the deterministic cleaner
            self._send(500, {"error": str(e)})
        finally:
            _last[0] = time.time()

    def log_message(self, *a):  # silence the default request logging
        pass


def main():
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
