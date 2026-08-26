#!/usr/bin/env bash
# Runs on the HOST before container start (devcontainer.json initializeCommand).
# Fetches secrets from the macOS Keychain into .devcontainer/.env, and derives
# .devcontainer/.env.docker from it for `runArgs --env-file`. Both are
# gitignored by the .gitignore in this directory, and SEC-001 depends on those
# lines staying there.
#
# **Nothing here is committed and nothing here is a project secret store.** The
# Keychain is the store; this script copies from it into a file the container
# reads and git never sees.
#
# Service names are generic (no per-repo prefix) so one host-side credential
# store is reused across projects. Prefix any name with the checkout directory
# in UPPER_SNAKE_CASE to override it for one project — a checkout in `my-app`
# looks for `MY_APP_GITHUB_TOKEN` before `GITHUB_TOKEN`.
#
# **Adding a value:** add one `fetch_secret` call and one `if [ -n ... ]` block.
# Quote a value that may contain a space (a person's name will; a token will
# not) — the derived `.env.docker` strips the quotes again, and the comment
# above that `sed` explains why both files exist.
set -euo pipefail

echo "==> Fetching secrets from Keychain..."
: > .devcontainer/.env

PROJECT_PREFIX=$(basename "$PWD" | tr '[:lower:]-' '[:upper:]_')

# Tries ${PROJECT_PREFIX}_${2}, then ${2}, writing the value into the variable
# named by $1. Sets LAST_SECRET_KEY to the hit, so the report below says which
# entry answered rather than only that one did.
#
# Run directly, never via command substitution, so these assignments land in the
# caller's shell rather than in a throwaway subshell.
fetch_secret() {
  local __outvar="$1" name="$2" prefixed="${PROJECT_PREFIX}_${2}" value
  value=$(security find-generic-password -a "$USER" -s "$prefixed" -w 2>/dev/null) || true
  if [ -n "$value" ]; then
    LAST_SECRET_KEY="$prefixed"
  else
    value=$(security find-generic-password -a "$USER" -s "$name" -w 2>/dev/null) || true
    LAST_SECRET_KEY="$name"
  fi
  printf -v "$__outvar" '%s' "$value"
}

# The one required value: without it the container starts and Claude Code cannot
# authenticate, which is a failure better reported here than discovered inside.
fetch_secret CLAUDE_CODE_OAUTH_TOKEN "CLAUDE_OAUTH_TOKEN"
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  echo "  ✗ No Claude Code OAuth token in Keychain."
  echo "    Run 'claude setup-token' on your Mac, then:"
  echo "      security add-generic-password -a \"\$USER\" \\"
  echo "        -s \"CLAUDE_OAUTH_TOKEN\" -w \"sk-ant-oat01-...\""
  exit 1
fi
echo "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}" >> .devcontainer/.env
echo "  ✓ CLAUDE_CODE_OAUTH_TOKEN [${LAST_SECRET_KEY}]"

fetch_secret GITHUB_TOKEN "GITHUB_TOKEN"
if [ -n "$GITHUB_TOKEN" ]; then
  echo "GITHUB_TOKEN=${GITHUB_TOKEN}" >> .devcontainer/.env
  echo "  ✓ GITHUB_TOKEN [${LAST_SECRET_KEY}]"
fi

fetch_secret GIT_AUTHOR_NAME "GIT_AUTHOR_NAME"
if [ -n "$GIT_AUTHOR_NAME" ]; then
  {
    echo "GIT_AUTHOR_NAME=\"${GIT_AUTHOR_NAME}\""
    echo "GIT_COMMITTER_NAME=\"${GIT_AUTHOR_NAME}\""
  } >> .devcontainer/.env
  echo "  ✓ GIT_AUTHOR_NAME [${LAST_SECRET_KEY}]"
fi

fetch_secret GIT_AUTHOR_EMAIL "GIT_AUTHOR_EMAIL"
if [ -n "$GIT_AUTHOR_EMAIL" ]; then
  {
    echo "GIT_AUTHOR_EMAIL=\"${GIT_AUTHOR_EMAIL}\""
    echo "GIT_COMMITTER_EMAIL=\"${GIT_AUTHOR_EMAIL}\""
  } >> .devcontainer/.env
  echo "  ✓ GIT_AUTHOR_EMAIL [${LAST_SECRET_KEY}]"
fi

# Two consumers read these values with incompatible parsers, so they get two
# files. `.env` is sourced as shell by check-auth.sh (`set -a; . .env`), where a
# value containing a space must be quoted or the shell splits it — that is what
# the quotes above are for. Docker's --env-file does no shell parsing at all: it
# takes everything after the `=` verbatim, so those same quotes would land
# inside the value. It therefore reads a copy with the surrounding pair removed.
#
# Derived rather than written twice, so the Keychain lookups above stay the one
# source of both files. A template that fetches only tokens will not notice the
# difference; one that fetches a person's name will.
sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)="(.*)"$/\1=\2/' \
  .devcontainer/.env > .devcontainer/.env.docker
chmod 600 .devcontainer/.env.docker

echo "  ✓ Written to .devcontainer/.env (sourced) and .env.docker (--env-file)"
