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
if rg -q 'let expanded = panel\.frame\.height >' "$ROOT/RonaldinhoPet/main.swift"; then
  echo "Panel expansion must not be inferred from rounded window geometry." >&2
  exit 1
fi
HELPER="$RONALDINHO_BUILD_ROOT/RonaldinhoPet.app/Contents/Resources/RonaldinhoPetState"
KING_ANIMATIONS="$RONALDINHO_BUILD_ROOT/RonaldinhoPet.app/Contents/Resources/pets/king-23/animations"
CREATOR_SKILL="$ROOT/codex-skill/create-editable-pet"
python3 "$CREATOR_SKILL/scripts/pet_pack.py" validate "$ROOT/pets/king-23"
PACK_REPO="$TEST_ROOT/pack repo"
mkdir -p "$PACK_REPO/pets" "$PACK_REPO/RonaldinhoPet"
touch "$PACK_REPO/RonaldinhoPet/main.swift"
python3 "$CREATOR_SKILL/scripts/pet_pack.py" scaffold "$PACK_REPO" sample-pet "Sample Pet" >/dev/null
grep -q '"displayName": "Sample Pet"' "$PACK_REPO/pets/sample-pet/pet.json"
test "$(find "$KING_ANIMATIONS" -type f -name '*.png' | wc -l | tr -d ' ')" = 9
for animation in "$KING_ANIMATIONS"/*.png; do
  sips -g hasAlpha "$animation" | grep -q 'hasAlpha: yes'
done

for fixture in claude-session-start claude-prompt claude-permission claude-stop; do
  "$HELPER" ingest claude < "$ROOT/tests/fixtures/${fixture}.json"
done

"$HELPER" inspect claude fixture-session | grep -q '"state":"completed"'
"$HELPER" inspect claude fixture-session | grep -q '"turn":1'

# A main agent waiting on delegated work has not finished.
printf '%s\n' '{"session_id":"delegated","hook_event_name":"UserPromptSubmit"}' | "$HELPER" ingest claude
printf '%s\n' '{"session_id":"delegated","hook_event_name":"Stop","background_tasks":[{"agent_id":"worker-1"}]}' | "$HELPER" ingest claude
"$HELPER" inspect claude delegated | grep -q '"state":"running"'
"$HELPER" inspect claude delegated | grep -q 'waiting for agents'

# Subagent lifecycle keeps the parent active even when Stop omits background_tasks.
printf '%s\n' '{"session_id":"tracked-agents","hook_event_name":"UserPromptSubmit"}' | "$HELPER" ingest claude
printf '%s\n' '{"session_id":"tracked-agents","hook_event_name":"SubagentStart","agent_id":"worker-1"}' | "$HELPER" ingest claude
printf '%s\n' '{"session_id":"tracked-agents","hook_event_name":"Stop"}' | "$HELPER" ingest claude
"$HELPER" inspect claude tracked-agents | grep -q 'waiting for agents'
printf '%s\n' '{"session_id":"tracked-agents","hook_event_name":"SubagentStop","agent_id":"worker-1"}' | "$HELPER" ingest claude
printf '%s\n' '{"session_id":"tracked-agents","hook_event_name":"Stop"}' | "$HELPER" ingest claude
"$HELPER" inspect claude tracked-agents | grep -q '"state":"completed"'

# Activity arriving after Stop cannot reopen the completed turn.
printf '%s\n' '{"session_id":"fixture-session","hook_event_name":"PostToolUse"}' | "$HELPER" ingest claude
"$HELPER" inspect claude fixture-session | grep -q '"state":"completed"'

# The same session id from another source gets another file.
printf '%s\n' '{"session_id":"fixture-session","hook_event_name":"UserPromptSubmit"}' | "$HELPER" ingest codex
test "$(find "$RONALDINHO_PET_ROOT/sessions" -type f -name '*.json' | wc -l | tr -d ' ')" = 4
"$HELPER" inspect codex fixture-session | grep -q 'Codex is thinking'
"$HELPER" inspect codex fixture-session | grep -q '"applicationBundleID":"com.openai.codex"'

# Codex may auto-review a permission request; it is not user input yet.
printf '%s\n' '{"session_id":"codex-auto-approval","hook_event_name":"UserPromptSubmit"}' | "$HELPER" ingest codex
printf '%s\n' '{"session_id":"codex-auto-approval","hook_event_name":"PermissionRequest"}' | "$HELPER" ingest codex
"$HELPER" inspect codex codex-auto-approval | grep -q '"state":"running"'
"$HELPER" inspect codex codex-auto-approval | grep -q 'checking permission'

# Concurrent updates remain valid JSON under the per-session lock.
printf '%s\n' '{"session_id":"concurrent","hook_event_name":"UserPromptSubmit"}' | "$HELPER" ingest claude
for _ in {1..100}; do
  printf '%s\n' '{"session_id":"concurrent","hook_event_name":"PostToolUse"}' | "$HELPER" ingest claude &
done
wait
test "$("$HELPER" validate)" = 6

SDK_PATH="$(xcrun --show-sdk-path)"
SDK_VERSION="$(xcrun --show-sdk-version)"
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx${SDK_VERSION}" \
  "$ROOT/RonaldinhoPet/StateModel.swift" "$ROOT/tests/state-model-tests.swift" \
  -o "$TEST_ROOT/state-model-tests"
"$TEST_ROOT/state-model-tests"

swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx${SDK_VERSION}" \
  "$ROOT/RonaldinhoPet/Host.swift" "$ROOT/RonaldinhoPet/configure-hooks.swift" -o "$TEST_ROOT/configure-hooks"
mkdir -p "$RONALDINHO_CONFIG_HOME/.claude"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"keep-me"}]}]},"secretLikeSetting":"preserved"}' \
  > "$RONALDINHO_CONFIG_HOME/.claude/settings.json"
INSTALL_ROOT="$TEST_ROOT/install root"
mkdir -p "$INSTALL_ROOT/RonaldinhoPet.app/Contents/Resources"
cp "$HELPER" "$INSTALL_ROOT/RonaldinhoPet.app/Contents/Resources/RonaldinhoPetState"
cp "$ROOT/RonaldinhoPet/show-pet.sh" "$INSTALL_ROOT/show-pet.sh"
"$TEST_ROOT/configure-hooks" "$INSTALL_ROOT" claude install >/dev/null
grep -q '/usr/bin/open -a' "$RONALDINHO_CONFIG_HOME/.claude/commands/pet.md"
if grep -q 'show-pet.sh' "$RONALDINHO_CONFIG_HOME/.claude/commands/pet.md"; then
  echo "Claude /pet still executes the quarantinable wrapper." >&2
  exit 1
fi
FIRST_HASH="$(shasum -a 256 "$RONALDINHO_CONFIG_HOME/.claude/settings.json")"
"$TEST_ROOT/configure-hooks" "$INSTALL_ROOT" claude install >/dev/null
test "$FIRST_HASH" = "$(shasum -a 256 "$RONALDINHO_CONFIG_HOME/.claude/settings.json")"
grep -q 'keep-me' "$RONALDINHO_CONFIG_HOME/.claude/settings.json"
grep -q 'secretLikeSetting' "$RONALDINHO_CONFIG_HOME/.claude/settings.json"
test "$("$TEST_ROOT/configure-hooks" "$INSTALL_ROOT" claude status)" = connected
"$TEST_ROOT/configure-hooks" "$INSTALL_ROOT" codex install >/dev/null
test "$(grep -c 'RonaldinhoPetState' "$RONALDINHO_CONFIG_HOME/.claude/settings.json")" = 13
test "$(grep -c 'RonaldinhoPetState' "$RONALDINHO_CONFIG_HOME/.codex/hooks.json")" = 14

# A prebuilt release installs without invoking the source build.
PREBUILT_ROOT="$TEST_ROOT/prebuilt"
PREBUILT_HOME="$TEST_ROOT/prebuilt home"
mkdir -p "$PREBUILT_ROOT" "$PREBUILT_HOME/.claude" "$PREBUILT_HOME/.codex"
ditto "$RONALDINHO_BUILD_ROOT/RonaldinhoPet.app" "$PREBUILT_ROOT/RonaldinhoPet.app"
HOME="$PREBUILT_HOME" RONALDINHO_CONFIG_HOME="$PREBUILT_HOME" \
  RONALDINHO_PREBUILT_ROOT="$PREBUILT_ROOT" RONALDINHO_BUILD_ROOT="$TEST_ROOT/should-not-build" \
  RONALDINHO_SKIP_HOST_CHECK=true RONALDINHO_SKIP_LAUNCH=true zsh "$ROOT/install.sh" >/dev/null
test -x "$PREBUILT_HOME/Library/Application Support/RonaldinhoPet/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet"
test ! -e "$TEST_ROOT/should-not-build"

# The public remote installer verifies and installs a release without clone/Xcode.
REMOTE_RELEASE="$TEST_ROOT/remote-release"
REMOTE_PACKAGE="$TEST_ROOT/remote package/Ronaldinho Pet"
REMOTE_HOME="$TEST_ROOT/remote home"
mkdir -p "$REMOTE_RELEASE" "$REMOTE_PACKAGE/prebuilt" "$REMOTE_PACKAGE/RonaldinhoPet" "$REMOTE_HOME/.claude" "$REMOTE_HOME/.codex"
ditto "$RONALDINHO_BUILD_ROOT/RonaldinhoPet.app" "$REMOTE_PACKAGE/prebuilt/RonaldinhoPet.app"
cp "$ROOT/install.sh" "$ROOT/uninstall.sh" "$REMOTE_PACKAGE/"
cp "$ROOT/RonaldinhoPet/show-pet.sh" "$ROOT/RonaldinhoPet/spritesheet.webp" "$REMOTE_PACKAGE/RonaldinhoPet/"
chmod +x "$REMOTE_PACKAGE"/*.sh
ditto -c -k --keepParent "$REMOTE_PACKAGE" "$REMOTE_RELEASE/RonaldinhoPet-test-macos-universal.zip"
(cd "$REMOTE_RELEASE" && shasum -a 256 RonaldinhoPet-test-macos-universal.zip > RonaldinhoPet-test-macos-universal.sha256)
HOME="$REMOTE_HOME" RONALDINHO_CONFIG_HOME="$REMOTE_HOME" RONALDINHO_TAG=vtest \
  RONALDINHO_DOWNLOAD_BASE="file://$REMOTE_RELEASE" RONALDINHO_SKIP_HOST_CHECK=true RONALDINHO_SKIP_LAUNCH=true \
  zsh "$ROOT/install-remote.sh" >/dev/null
test -x "$REMOTE_HOME/Library/Application Support/RonaldinhoPet/RonaldinhoPet.app/Contents/MacOS/RonaldinhoPet"

# Exercise the public installer twice in an isolated home, then uninstall.
PUBLIC_HOME="$TEST_ROOT/public home"
mkdir -p "$PUBLIC_HOME/.claude" "$PUBLIC_HOME/.codex"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"keep-claude"}]}]}}' > "$PUBLIC_HOME/.claude/settings.json"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"keep-codex"}]}]}}' > "$PUBLIC_HOME/.codex/hooks.json"
HOME="$PUBLIC_HOME" RONALDINHO_CONFIG_HOME="$PUBLIC_HOME" RONALDINHO_SKIP_HOST_CHECK=true RONALDINHO_SKIP_LAUNCH=true zsh "$ROOT/install.sh" >/dev/null
test -f "$PUBLIC_HOME/.codex/skills/ronaldinho-pet/SKILL.md"
test -f "$PUBLIC_HOME/.codex/skills/create-editable-pet/SKILL.md"
grep -q 'name: ronaldinho-pet' "$PUBLIC_HOME/.codex/skills/ronaldinho-pet/SKILL.md"
grep -q 'name: create-editable-pet' "$PUBLIC_HOME/.codex/skills/create-editable-pet/SKILL.md"
PUBLIC_HASH="$(shasum -a 256 "$PUBLIC_HOME/.claude/settings.json" "$PUBLIC_HOME/.codex/hooks.json")"
BACKUP_COUNT="$(find "$PUBLIC_HOME" -name '*.ronaldinho-backup-*' | wc -l | tr -d ' ')"
HOME="$PUBLIC_HOME" RONALDINHO_CONFIG_HOME="$PUBLIC_HOME" RONALDINHO_SKIP_HOST_CHECK=true RONALDINHO_SKIP_LAUNCH=true zsh "$ROOT/install.sh" >/dev/null
test "$PUBLIC_HASH" = "$(shasum -a 256 "$PUBLIC_HOME/.claude/settings.json" "$PUBLIC_HOME/.codex/hooks.json")"
test "$BACKUP_COUNT" = "$(find "$PUBLIC_HOME" -name '*.ronaldinho-backup-*' | wc -l | tr -d ' ')"
HOME="$PUBLIC_HOME" RONALDINHO_CONFIG_HOME="$PUBLIC_HOME" zsh "$ROOT/uninstall.sh" >/dev/null
grep -q keep-claude "$PUBLIC_HOME/.claude/settings.json"
grep -q keep-codex "$PUBLIC_HOME/.codex/hooks.json"
if rg -q RonaldinhoPetState "$PUBLIC_HOME/.claude/settings.json" "$PUBLIC_HOME/.codex/hooks.json"; then
  echo "Uninstall left owned hooks behind." >&2
  exit 1
fi
test ! -e "$PUBLIC_HOME/.codex/skills/ronaldinho-pet"
test ! -e "$PUBLIC_HOME/.codex/skills/create-editable-pet"

if rg -n '/Users/felipefrf|development/personal' "$ROOT" \
  -g '!EXECUTION_PLAN.md' -g '!test.sh' -g '!*.webp' -g '!.git/**'; then
  echo "Personal path found in publishable files." >&2
  exit 1
fi

echo "All tests passed."
