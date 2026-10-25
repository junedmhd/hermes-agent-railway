#!/usr/bin/env bash
set -e

AUTO_UPDATE="${AUTO_UPDATE:-true}"

if [ "$AUTO_UPDATE" = "true" ]; then
  echo "Checking for Hermes updates..."
  cd /opt/hermes-agent
  if git pull --recurse-submodules 2>&1 | grep -v 'Already up to date'; then
    echo "Updating dependencies..."
    VIRTUAL_ENV=/opt/hermes-agent/venv uv pip install -e ".[all,telegram]" --quiet
    echo "Update complete."
  else
    echo "Already up to date."
  fi
fi

# Let the terminal tool see the repo link's variables. Hermes strips GITHUB_TOKEN and
# HERMES_* from every command by design, so these use neutral names and an explicit
# allowlist (terminal.env_passthrough). Idempotent: rewrites only that one key.
/opt/hermes-agent/venv/bin/python - <<'PY' || echo "env_passthrough: not set"
from pathlib import Path
from ruamel.yaml import YAML
p = Path("/root/.hermes/config.yaml")
y = YAML()
cfg = y.load(p.read_text()) if p.exists() else {}
cfg = cfg or {}
want = ["LIFEOS_READ_TOKEN", "NAIB_AGENT_TOKEN", "NAIB_AGENT_URL"]
term = cfg.setdefault("terminal", {})
have = list(term.get("env_passthrough") or [])
if any(n not in have for n in want):
    term["env_passthrough"] = have + [n for n in want if n not in have]
    with p.open("w") as f:
        y.dump(cfg, f)
    print("env_passthrough: updated")
else:
    print("env_passthrough: already set")
PY

hermes dashboard --host 127.0.0.1 --port 9119 --no-open &

exec python /auth_proxy.py
