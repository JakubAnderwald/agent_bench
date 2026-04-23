#!/usr/bin/env bash
# One-time setup: clone repos and build per-case templates.
# Idempotent — safe to rerun.

set -euo pipefail
cd "$(dirname "$0")"

log() { printf "\033[36m[prepare]\033[0m %s\n" "$*"; }
need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }

need git
need pnpm
need node
need tar
need python3
need uv || true  # optional; recommended for TC5

# --- clone read-only repos ---
if [ ! -d repos/ky ]; then
  log "cloning ky"
  git clone --depth 1 --branch v1.7.2 https://github.com/sindresorhus/ky.git repos/ky
fi

if [ ! -d repos/express ]; then
  log "cloning express"
  git clone --depth 1 --branch 4.21.1 https://github.com/expressjs/express.git repos/express
fi

# --- nextjs fresh template (TC2, TC3 base) ---
if [ ! -f templates/nextjs.tar.gz ]; then
  log "building nextjs template (slow, ~1 min, happens once)"
  tmp=$(mktemp -d)
  (
    cd "$tmp"
    pnpm create next-app@latest app \
      --ts --tailwind --app --eslint \
      --no-src-dir --no-import-alias \
      --use-pnpm --yes \
      --turbopack >/dev/null 2>&1 || \
    pnpm create next-app@latest app \
      --ts --tailwind --app --eslint \
      --no-src-dir --no-import-alias \
      --use-pnpm --yes >/dev/null
  )
  rm -rf "$tmp/app/.git"
  # strip node_modules — agents install themselves OR we pre-install?
  # Pre-install so timings don't include npm install noise.
  (cd "$tmp/app" && pnpm install --silent >/dev/null)
  tar czf templates/nextjs.tar.gz -C "$tmp/app" .
  rm -rf "$tmp"
  log "nextjs template: $(du -h templates/nextjs.tar.gz | cut -f1)"
fi

# --- TC4 seed (bugfix mini-repo) ---
if [ ! -f templates/tc4-bugfix.tar.gz ]; then
  log "building tc4 bugfix seed"
  tmp=$(mktemp -d)
  (
    cd "$tmp"
    npm init -y >/dev/null
    npm i -D --silent vitest >/dev/null 2>&1
    mkdir -p src test
    cat > src/slugify.js <<'JS'
export function slugify(input) {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/, "");
}
JS
    cat > test/slugify.test.js <<'JS'
import { describe, it, expect } from "vitest";
import { slugify } from "../src/slugify.js";

describe("slugify", () => {
  it("lowercases and replaces spaces", () => {
    expect(slugify("Hello World")).toBe("hello-world");
  });
  it("strips repeated surrounding separators", () => {
    expect(slugify("  Hello, World!  ")).toBe("hello-world");
  });
  it("collapses multiple separators in the middle", () => {
    expect(slugify("foo -- bar")).toBe("foo-bar");
  });
});
JS
    cat > package.json <<'JSON'
{
  "name": "bench-bugfix",
  "version": "1.0.0",
  "type": "module",
  "scripts": { "test": "vitest run" },
  "devDependencies": { "vitest": "^2.1.0" }
}
JSON
    npm i --silent >/dev/null 2>&1
  )
  tar czf templates/tc4-bugfix.tar.gz -C "$tmp" .
  rm -rf "$tmp"
fi

# --- TC5 seed (FastAPI mini-app) ---
if [ ! -f templates/tc5-fastapi.tar.gz ]; then
  log "building tc5 fastapi seed"
  tmp=$(mktemp -d)
  (
    cd "$tmp"
    mkdir -p app tests
    cat > app/__init__.py <<'PY'
PY
    cat > app/main.py <<'PY'
from fastapi import FastAPI

app = FastAPI(title="bench-fastapi")


@app.get("/")
def root():
    return {"message": "hello"}


@app.get("/items/{item_id}")
def read_item(item_id: int):
    return {"item_id": item_id}
PY
    cat > tests/__init__.py <<'PY'
PY
    cat > tests/test_items.py <<'PY'
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_root():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json() == {"message": "hello"}


def test_item():
    r = client.get("/items/42")
    assert r.status_code == 200
    assert r.json() == {"item_id": 42}
PY
    cat > requirements.txt <<'TXT'
fastapi==0.115.0
httpx==0.27.2
pytest==8.3.3
TXT
    cat > pytest.ini <<'INI'
[pytest]
testpaths = tests
INI
    # pre-install deps so per-run setup is fast
    if command -v uv >/dev/null; then
      uv venv .venv >/dev/null 2>&1
      uv pip install --python .venv/bin/python -r requirements.txt >/dev/null
    else
      python3 -m venv .venv
      .venv/bin/pip install -q -r requirements.txt
    fi
  )
  tar czf templates/tc5-fastapi.tar.gz -C "$tmp" .
  rm -rf "$tmp"
fi

log "done. run: ./bench.sh  (or ./race.sh tc2 for a screencast demo)"
