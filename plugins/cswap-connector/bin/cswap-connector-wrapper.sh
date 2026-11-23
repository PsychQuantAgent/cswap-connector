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

if [ ! -x "$BIN" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$VERSION" ]; then
  # pending-hint runs before every prompt and has nothing to deliver until
  # stop-failure (which needs the binary) has run, so it never downloads.
  [ "$SUB" = "pending-hint" ] && exit 0
  mkdir -p "$BIN_DIR" || fail "cannot create $BIN_DIR"
  # After a failed download, wait 15 minutes before trying again.
  if [ -f "$FAILED" ] && [ $(( $(date +%s) - $(cat "$FAILED" 2>/dev/null || echo 0) )) -lt 900 ]; then
    fail "binary not installed yet (download retry in under 15 min)"
  fi
  BASE="https://github.com/$REPO/releases/download/v$VERSION"
  TMP=$(mktemp "$BIN_DIR/download.XXXXXX") || fail "cannot create a temporary file"
  if ! curl -fsL --max-time 6 "$BASE/cswap-connector" -o "$TMP"; then
    rm -f "$TMP"; date +%s > "$FAILED"; fail "could not download the v$VERSION binary"
  fi
  EXPECTED=$(curl -fsL --max-time 3 "$BASE/cswap-connector.sha256" | awk '{print $1}')
  ACTUAL=$(shasum -a 256 "$TMP" | awk '{print $1}')
  if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
    rm -f "$TMP"; date +%s > "$FAILED"; fail "checksum mismatch for the v$VERSION binary"
  fi
  chmod 755 "$TMP" && mv -f "$TMP" "$BIN" && printf '%s\n' "$VERSION" > "$STAMP" || fail "cannot install the binary"
  rm -f "$FAILED"
fi

exec "$BIN" "$@"
