#!/bin/sh
# Resolves the cswap-connector binary and runs one subcommand.
# Fail open: on any problem, `session-context` prints one line, `mcp` prints
# one line to stderr, every other subcommand prints nothing, and the script
# exits 0.
#
# Lookup order:
#   1. $CSWAP_CONNECTOR_BIN (development override, e.g. a local `swift build`)
#   2. ${CLAUDE_PLUGIN_DATA}/bin/cswap-connector, downloaded from the GitHub
#      Release matching this plugin's version and checked against its .sha256
#
# The binary is about 11 MB; one measured download took 8.7 s, longer than the
# 8 s SessionStart hook budget. So hooks never download in the foreground:
# they start a background install and fail open for that session. The MCP
# server, which may wait, installs in the foreground.

SUB="${1:-}"
REPO="PsychQuantAgent/cswap-connector"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/cswap-connector}"

fail() {
  [ "$SUB" = "session-context" ] && echo "cswap-connector: $1"
  [ "$SUB" = "mcp" ] && echo "cswap-connector: $1" >&2
  exit 0
}

[ "$(uname -s)" = "Darwin" ] || fail "unsupported platform"

if [ -n "${CSWAP_CONNECTOR_BIN:-}" ]; then
  [ -x "$CSWAP_CONNECTOR_BIN" ] || fail "CSWAP_CONNECTOR_BIN is not executable"
  exec "$CSWAP_CONNECTOR_BIN" "$@"
fi

VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/plugin.json" | head -n 1)
[ -n "$VERSION" ] || fail "cannot read plugin version"

BIN_DIR="$DATA/bin"
BIN="$BIN_DIR/cswap-connector"
STAMP="$BIN_DIR/version"
FAILED="$BIN_DIR/last-download-failure"
LOCK="$BIN_DIR/install.lock"

installed() {
  [ -x "$BIN" ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$VERSION" ]
}

# Downloads and verifies the release binary. Returns non-zero on failure.
install() {
  mkdir -p "$BIN_DIR" || return 1
  # One installer at a time; a lock older than 10 minutes is considered stale.
  if ! mkdir "$LOCK" 2>/dev/null; then
    find "$LOCK" -maxdepth 0 -mmin +10 -exec rmdir {} \; 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || return 1
  fi
  BASE="https://github.com/$REPO/releases/download/v$VERSION"
  TMP=$(mktemp "$BIN_DIR/download.XXXXXX") || { rmdir "$LOCK"; return 1; }
  if curl -fsL --max-time 120 "$BASE/cswap-connector" -o "$TMP" \
     && EXPECTED=$(curl -fsL --max-time 20 "$BASE/cswap-connector.sha256" | awk '{print $1}') \
     && [ -n "$EXPECTED" ] && [ "$EXPECTED" = "$(shasum -a 256 "$TMP" | awk '{print $1}')" ] \
     && chmod 755 "$TMP" && mv -f "$TMP" "$BIN" && printf '%s\n' "$VERSION" > "$STAMP"; then
    rm -f "$FAILED"; rmdir "$LOCK"; return 0
  fi
  rm -f "$TMP"; date +%s > "$FAILED"; rmdir "$LOCK"; return 1
}

recently_failed() {
  [ -f "$FAILED" ] && [ $(( $(date +%s) - $(cat "$FAILED" 2>/dev/null || echo 0) )) -lt 900 ]
}

if [ "$SUB" = "__install" ]; then
  install
  exit 0
fi

if ! installed; then
  case "$SUB" in
    pending-hint)
      # Runs before every prompt; nothing to deliver until stop-failure (which
      # needs the binary) has run.
      exit 0 ;;
    mcp)
      recently_failed && fail "binary download failed recently; retry in under 15 min"
      install || fail "could not install the v$VERSION binary" ;;
    *)
      recently_failed && fail "binary download failed recently; retry in under 15 min"
      [ -d "$LOCK" ] || nohup "$0" __install >/dev/null 2>&1 &
      fail "installing the v$VERSION binary in the background; account usage appears from the next session" ;;
  esac
fi

exec "$BIN" "$@"
