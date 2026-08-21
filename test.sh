#!/bin/zsh
set -euo pipefail
setopt NO_BG_NICE

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ronaldinho-pet-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

export RONALDINHO_PET_ROOT="$TEST_ROOT/state root"
export RONALDINHO_CONFIG_HOME="$TEST_ROOT/home with space"
export RONALDINHO_BUILD_ROOT="$TEST_ROOT/build"
export CLANG_MODULE_CACHE_PATH="$TEST_ROOT/module-cache"

zsh "$ROOT/RonaldinhoPet/build-app.sh" "$ROOT/RonaldinhoPet/spritesheet.webp" >/dev/null
HELPER="$RONALDINHO_BUILD_ROOT/RonaldinhoPet.app/Contents/Resources/RonaldinhoPetState"

for fixture in claude-session-start claude-prompt claude-permission claude-stop; do
  "$HELPER" ingest claude < "$ROOT/tests/fixtures/${fixture}.json"
done

"$HELPER" inspect claude fixture-session | grep -q '"state":"completed"'
"$HELPER" inspect claude fixture-session | grep -q '"turn":1'

# Activity arriving after Stop cannot reopen the completed turn.
printf '%s\n' '{"session_id":"fixture-session","hook_event_name":"PostToolUse"}' | "$HELPER" ingest claude
"$HELPER" inspect claude fixture-session | grep -q '"state":"completed"'

# The same session id from another source gets another file.
printf '%s\n' '{"session_id":"fixture-session","hook_event_name":"UserPromptSubmit"}' | "$HELPER" ingest codex
test "$(find "$RONALDINHO_PET_ROOT/sessions" -type f -name '*.json' | wc -l | tr -d ' ')" = 2

# Concurrent updates remain valid JSON under the per-session lock.
printf '%s\n' '{"session_id":"concurrent","hook_event_name":"UserPromptSubmit"}' | "$HELPER" ingest claude
for _ in {1..100}; do
  printf '%s\n' '{"session_id":"concurrent","hook_event_name":"PostToolUse"}' | "$HELPER" ingest claude &
done
wait
test "$("$HELPER" validate)" = 3

SDK_PATH="$(xcrun --show-sdk-path)"
SDK_VERSION="$(xcrun --show-sdk-version)"
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx${SDK_VERSION}" \
  "$ROOT/RonaldinhoPet/StateModel.swift" "$ROOT/tests/state-model-tests.swift" \
  -o "$TEST_ROOT/state-model-tests"
"$TEST_ROOT/state-model-tests"

swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx${SDK_VERSION}" \
  "$ROOT/RonaldinhoPet/configure-hooks.swift" -o "$TEST_ROOT/configure-hooks"
mkdir -p "$RONALDINHO_CONFIG_HOME/.claude"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"keep-me"}]}]},"secretLikeSetting":"preserved"}' \
  > "$RONALDINHO_CONFIG_HOME/.claude/settings.json"
INSTALL_ROOT="$TEST_ROOT/install root"
mkdir -p "$INSTALL_ROOT/RonaldinhoPet.app/Contents/Resources"
cp "$HELPER" "$INSTALL_ROOT/RonaldinhoPet.app/Contents/Resources/RonaldinhoPetState"
cp "$ROOT/RonaldinhoPet/show-pet.sh" "$INSTALL_ROOT/show-pet.sh"
"$TEST_ROOT/configure-hooks" "$INSTALL_ROOT" claude install >/dev/null
FIRST_HASH="$(shasum -a 256 "$RONALDINHO_CONFIG_HOME/.claude/settings.json")"
"$TEST_ROOT/configure-hooks" "$INSTALL_ROOT" claude install >/dev/null
test "$FIRST_HASH" = "$(shasum -a 256 "$RONALDINHO_CONFIG_HOME/.claude/settings.json")"
grep -q 'keep-me' "$RONALDINHO_CONFIG_HOME/.claude/settings.json"
grep -q 'secretLikeSetting' "$RONALDINHO_CONFIG_HOME/.claude/settings.json"
test "$(grep -c 'RonaldinhoPetState' "$RONALDINHO_CONFIG_HOME/.claude/settings.json")" = 9
"$TEST_ROOT/configure-hooks" "$INSTALL_ROOT" codex install >/dev/null
test "$(grep -c 'RonaldinhoPetState' "$RONALDINHO_CONFIG_HOME/.codex/hooks.json")" = 9

# Exercise the public installer twice in an isolated home, then uninstall.
PUBLIC_HOME="$TEST_ROOT/public home"
mkdir -p "$PUBLIC_HOME/.claude" "$PUBLIC_HOME/.codex"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"keep-claude"}]}]}}' > "$PUBLIC_HOME/.claude/settings.json"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"keep-codex"}]}]}}' > "$PUBLIC_HOME/.codex/hooks.json"
HOME="$PUBLIC_HOME" RONALDINHO_CONFIG_HOME="$PUBLIC_HOME" RONALDINHO_SKIP_LAUNCH=true zsh "$ROOT/install.sh" >/dev/null
PUBLIC_HASH="$(shasum -a 256 "$PUBLIC_HOME/.claude/settings.json" "$PUBLIC_HOME/.codex/hooks.json")"
BACKUP_COUNT="$(find "$PUBLIC_HOME" -name '*.ronaldinho-backup-*' | wc -l | tr -d ' ')"
HOME="$PUBLIC_HOME" RONALDINHO_CONFIG_HOME="$PUBLIC_HOME" RONALDINHO_SKIP_LAUNCH=true zsh "$ROOT/install.sh" >/dev/null
test "$PUBLIC_HASH" = "$(shasum -a 256 "$PUBLIC_HOME/.claude/settings.json" "$PUBLIC_HOME/.codex/hooks.json")"
test "$BACKUP_COUNT" = "$(find "$PUBLIC_HOME" -name '*.ronaldinho-backup-*' | wc -l | tr -d ' ')"
HOME="$PUBLIC_HOME" RONALDINHO_CONFIG_HOME="$PUBLIC_HOME" zsh "$ROOT/uninstall.sh" >/dev/null
grep -q keep-claude "$PUBLIC_HOME/.claude/settings.json"
grep -q keep-codex "$PUBLIC_HOME/.codex/hooks.json"
if rg -q RonaldinhoPetState "$PUBLIC_HOME/.claude/settings.json" "$PUBLIC_HOME/.codex/hooks.json"; then
  echo "Uninstall left owned hooks behind." >&2
  exit 1
fi

if rg -n '/Users/felipefrf|development/personal' "$ROOT" \
  -g '!EXECUTION_PLAN.md' -g '!test.sh' -g '!*.webp' -g '!.git/**'; then
  echo "Personal path found in publishable files." >&2
  exit 1
fi

echo "All tests passed."
