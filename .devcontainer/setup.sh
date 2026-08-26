#!/usr/bin/env bash
# Runs on container create (postCreateCommand).
#
# **This file pins no tool version, and that is a rule rather than an accident.**
# Phase 2's exit criterion reads: *the template pins no tool version by hand;
# every tool it installs is either sourced from a lockfile the consumer repo
# already commits, or from a single toolchain file — never a literal inside
# setup.sh.* A template that scatters pins through a shell script reproduces
# that problem in every repository that adopts the standard, and the consumer
# has no `tool_versions_match_register` of their own until they adopt the
# register too.
#
# So there are exactly three sources of a version here, and none of them is a
# literal somebody typed:
#
#   1. A lockfile this repository already commits. `npm ci` and `uv sync
#      --frozen` install what the lockfile says and nothing else.
#   2. A pinned devcontainer feature, resolved to a digest in
#      devcontainer-lock.json.
#   3. A double-brace placeholder substituted from the register you are
#      adopting. uv arrives this way, because it is the tool every
#      verification runs on, so no gate can install it — see the block below
#      and `docs/adr/0034-the-template-bootstraps-uv.md`.
#
# Anything else — a scanner, a linter, an analyser — is installed by the gate
# that owns the control it serves, which writes its own region into this file
# and stamps it. `gate-secrets` does that for the secret scanner;
# `gate-supply-chain` for the package manager where one is needed.
#
# Deliberately short. Per docs/03-devcontainer.md, anything long enough to need
# sectioning is doing work that belongs in the image or in a pinned feature.
set -euo pipefail

# The named volume mounts root-owned on first create.
sudo chown -R vscode:vscode /home/vscode/.claude

# **`claude update` must work, or the container is pinned to whatever the feature
# shipped.** The claude-code feature runs `npm install -g` as root, so the
# package tree it writes is root-owned while this container's user is vscode
# (BLD-001) — and `claude update` then fails with "Insufficient permissions to
# install update", on a release cadence of roughly one a day. Phase 4 met this
# stuck at 2.1.241 mid-adoption.
#
# Hand vscode the one package the feature owns; the surrounding node_modules and
# bin are already group-writable. The glob is a loop rather than a `chown` on
# the pattern so that a container without the feature is a no-op rather than an
# error.
for d in /usr/local/share/nvm/versions/node/*/lib/node_modules/@anthropic-ai; do
  [ -d "$d" ] && sudo chown -R vscode:vscode "$d"
done

# **Trust the workspace, or nothing here can read git.** On a macOS host the
# workspace is a bind mount, and git inside the container refuses it —
# "detected dubious ownership" — even though the directory and `.git` both stat
# as the container user. `git status` and `git add` may work while `git commit`
# and `git log` do not, which is worse than a clean failure: the first commands
# an adopter tries are the ones that succeed.
#
# It matters more here than in an ordinary project. **Every assert in this
# standard reads what git tracks**, so a repository git will not open reports
# nothing rather than reporting a violation — `register-check` says so in as
# many words and exits without a verdict.
#
# Scoped to this workspace, never `*`: the check exists to stop you running
# hooks out of a repository somebody else owns, and the one directory the
# container was created for is exactly the one to trust.
git config --global --add safe.directory "$PWD"

# uv, from the pinned release tarball, verified against the published sha256.
#
# **This is the one install that cannot wait for a gate**, which is why it is
# here rather than in a region some `gate-*` skill writes. Everything the
# standard asks you to run goes through `uv run register-check` — every gate's
# verify step, the pre-commit hooks for SUP-003, BLD-001 and DEV-001, and the CI
# job CI-001 requires. A gate cannot install the tool its own verification runs
# on. Phase 4 found this container with no uv at all, `setup.sh` calling
# `uv sync --frozen` a few lines below, and the guide telling the adopter to run
# `uv run register-check`.
#
# **The three values are placeholders, not pins**, and that is what keeps the
# rule at the top of this file true. They are copied out of the register you are
# adopting — `tools.uv.version` and `tools.uv.sha256` — so the version lives in
# the register and this file references it, rather than a second copy being
# written here by hand. `tool_versions_match_register` reconciles this file once
# `.devcontainer/setup.sh` is named in that tool's `pinned_at`.
#
# The assignments below are unquoted on purpose. That assert matches a tool name
# followed by a version across `@`, `=`, `:` or whitespace, so quoting the
# substituted value puts a quote where it looks for the separator and the pin is
# reported missing — a substituted file that reconciles against nothing, which
# is the silent-pass shape this standard keeps finding.
#
# The register pins **one** checksum, for x86_64. The other architecture's comes
# from the same release's checksum file on GitHub and is compared by nothing —
# a known gap recorded in `docs/09-phase-1.5-review.md`, carried here rather
# than hidden by shipping a single-architecture install.
#
# A feature was considered and rejected: the community uv feature curls the same
# tarball with no checksum and no signature, so `devcontainer-lock.json` would
# pin the installer and not the artefact — the measurement Phase 0.5 already
# made for uv and gitleaks (docs/adr/0034-the-template-bootstraps-uv.md).
# ee-control: SUP-001  ee-skill: gate-supply-chain@0.1.0  register: v0.24.0  register-contract: 30
#
# The stamp is at this block, never at the file. `.devcontainer/setup.sh`
# belongs to gate-build; the package-manager install inside it is SUP-001's
# locus, exactly as several gates write their own hooks into one
# `.pre-commit-config.yaml`. The version below was already correct against the
# register and was adopted rather than rewritten.
uv_version=0.12.5
case "$(uname -m)" in
  aarch64|arm64) uv_arch=aarch64 uv_sha=9bf43b4d1a07665bf64d4c4e710930b382321a785e0eb10aac07f46471f86a31 ;;
  *)             uv_arch=x86_64  uv_sha=68a509da24b06b4223a1c0175fb5eb5bc79342b76cbeff0cfe51ac3f5b17b6b2 ;;
esac
uv_dir="uv-${uv_arch}-unknown-linux-gnu"
curl -sSfL -o /tmp/uv.tgz \
  "https://github.com/astral-sh/uv/releases/download/${uv_version}/${uv_dir}.tar.gz"
echo "${uv_sha}  /tmp/uv.tgz" | sha256sum -c --quiet -
tar -xzf /tmp/uv.tgz -C /tmp --strip-components=1 "${uv_dir}/uv" "${uv_dir}/uvx"
sudo install /tmp/uv /tmp/uvx /usr/local/bin/
rm /tmp/uv.tgz /tmp/uv /tmp/uvx

# ee-control: SEC-001  ee-skill: gate-secrets@0.1.0  register: v0.24.0  register-contract: 30
#
# gitleaks, from the pinned release, verified against the published sha256.
# This is not a locus of SEC-001's own — the control declares pre-commit, ci and
# remote, and a developer environment is none of them. It is where the
# pre-commit locus's binary comes from, which is why the register lists this
# file in `tools.gitleaks.pinned_at` and `tool_versions_match_register`
# compares it against the CI install.
#
# The stamp is at this block, never at the file: `setup.sh` belongs to
# gate-build, and gate-supply-chain's uv block sits above this one.
#
# The register pins **one** checksum, for x86_64 — the same single-architecture
# gap the uv block above records. The aarch64 value comes from the same
# release's published checksums file and is compared by nothing.
gitleaks_version=8.30.1
case "$(uname -m)" in
  aarch64|arm64) gitleaks_arch=arm64 gitleaks_sha=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080 ;;
  *)             gitleaks_arch=x64   gitleaks_sha=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb ;;
esac
curl -sSfL -o /tmp/gitleaks.tgz \
  "https://github.com/gitleaks/gitleaks/releases/download/v${gitleaks_version}/gitleaks_${gitleaks_version}_linux_${gitleaks_arch}.tar.gz"
echo "${gitleaks_sha}  /tmp/gitleaks.tgz" | sha256sum -c --quiet -
tar -xzf /tmp/gitleaks.tgz -C /tmp gitleaks
sudo install /tmp/gitleaks /usr/local/bin/gitleaks
rm /tmp/gitleaks.tgz /tmp/gitleaks

# Install from whichever lockfiles this repository commits. Each is guarded by
# the lockfile's own presence rather than by a language guess: a repository is
# in an ecosystem when it has that ecosystem's lockfile, which is the same test
# SUP-001 applies.
if [ -f package-lock.json ]; then
  npm ci --no-audit --no-fund
fi

if [ -f uv.lock ]; then
  uv sync --frozen
elif [ -f poetry.lock ]; then
  poetry install --sync
fi

# **The git hook is installed on its own terms, not as a tail of a lockfile
# branch.** It used to hang off the `uv.lock` arm, so a repository that gained a
# lockfile *after* its container was created never got one — and Phase 4's
# consumer repo is exactly that: `.pre-commit-config.yaml` deployed and
# stamped, every locus reported wired, and `.git/hooks/pre-commit` absent. The
# gates read the config file, which is a statement of intent; the hook is
# whether anything runs. Declared and unreachable is the failure this standard
# exists to catch, and it had reached the artefact the standard itself deploys.
#
# `pre-commit` is reached the way its locus reaches it — through the package
# manager where a lockfile pins it, and only otherwise off `PATH`. An absent one
# is reported rather than installed unpinned.
if [ -f .pre-commit-config.yaml ]; then
  # Each arm asks whether the tool is *reachable that way* before using it, and
  # never whether a lockfile merely exists. A repository can have `uv.lock` and
  # no pre-commit in it — every repository does, between the gate that writes
  # the config and the gate that adds the dependency — and `uv run pre-commit`
  # then exits non-zero, which under `set -e` aborts container create. A
  # devcontainer that fails to build because a hook is not installed yet is a
  # worse failure than the missing hook.
  if [ -f uv.lock ] && uv run pre-commit --version >/dev/null 2>&1; then
    uv run pre-commit install
  elif [ -f poetry.lock ] && poetry run pre-commit --version >/dev/null 2>&1; then
    poetry run pre-commit install
  elif command -v pre-commit >/dev/null 2>&1; then
    pre-commit install
  else
    echo "note: .pre-commit-config.yaml exists and pre-commit is not installed," >&2
    echo "      so nothing runs at the pre-commit locus. Add it to a lockfile" >&2
    echo "      this repository commits, then re-run this script." >&2
  fi
fi

# The host ~/.gitconfig may name a credential-helper path that does not exist
# in this container.
if command -v gh >/dev/null 2>&1; then
  GH_BIN="$(command -v gh)"
  for host in github.com gist.github.com; do
    git config --global --unset-all "credential.https://${host}.helper" || true
    git config --global --add "credential.https://${host}.helper" \
      "!${GH_BIN} auth git-credential"
  done
fi
