# Ronaldinho Pet

A small macOS companion for Claude Code, Claude Desktop, Codex CLI, and Codex
App. It uses native hooks and keeps one state file per session, so concurrent
terminals do not overwrite each other.

## Install on macOS

### Terminal — one command

```sh
curl -fsSL https://raw.githubusercontent.com/felipefrf/ronaldinho-pet/main/install-remote.sh | zsh
```

This downloads the newest GitHub release, verifies its published SHA-256, and
runs the same installer used by the DMG. It does not clone the repository or
require Xcode.

### Download

Download the newest `macos-universal.dmg` from
[Releases](https://github.com/felipefrf/ronaldinho-pet/releases), open it, and
drag **RonaldinhoPet** to **Applications**. Open it and use **Connections** to
connect Claude and Codex. The prebuilt release works on Apple
Silicon and Intel Macs running macOS 13 or newer; Xcode is not required.

After launch, right-click Ronaldinho and choose **Connections…** to connect or
disconnect Claude and Codex without using the terminal.

Until the app has a Developer ID signature, macOS may require **right-click →
Open** the first time.

## Install from source

Requirements:

- macOS
- Xcode Command Line Tools (`xcode-select --install`)
- Claude Code/Desktop and/or Codex

```sh
git clone https://github.com/felipefrf/ronaldinho-pet.git
cd ronaldinho-pet
./install.sh
```

If Codex prompts about hooks, review and trust only the commands ending in
`RonaldinhoPetState ingest codex`. Then restart Claude and Codex.
In Codex App, open **Settings → Pets → Refresh** to select the native pet.

There are two intentional surfaces using the same sprite asset:

- the Codex App native pet lives inside Codex and its size is controlled under
  **Settings → Pets → Appearance → Pet size**;
- the floating companion combines Claude and Codex activity. Right-click it and
  drag the **Pet size** slider, or scroll anywhere over the companion for
  continuous sizing. This choice is persisted.

Right-click the floating companion and use **Pet** to switch between
**Ronaldinho** and the original basketball companion **King 23**.

The compact bar always shows Claude and Codex independently, including active
and finished counts. Click it to expand the fixed row for each host.

The installer:

- uses the universal prebuilt app, or builds locally for a source install;
- installs into `~/Library/Application Support/RonaldinhoPet`;
- merges its hooks without replacing existing hooks;
- installs the native Codex pet under `~/.codex/pets/ronaldinho-gaucho`;
- installs the `$ronaldinho-pet` skill for Codex App and CLI;
- creates timestamped configuration backups only when content changes;
- can be run repeatedly without duplicating entries.

Run `/pet` in Claude Code or `$ronaldinho-pet` in Codex App/CLI to show the
floating companion again. Codex reserves `/pet` for its native in-app pet.

## Concurrent sessions

Each `(host, session)` pair owns a separate atomic JSON snapshot. The companion
shows waiting sessions first, followed by unread failures, active work, and
completed work. Acknowledging one result does not clear another.

Silent running sessions become `unknown` after six hours; timeout never claims
that work completed. Old terminal/unknown records are eligible for cleanup after
30 days.

## Uninstall

Double-click **Uninstall Ronaldinho Pet** in the downloaded release, or run
`./uninstall.sh` from a source checkout.

From any terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/felipefrf/ronaldinho-pet/main/install-remote.sh | zsh -s -- uninstall
```

Owned hooks are removed exactly; unrelated settings remain. The app, state, and
native Codex pet are moved to Trash so removal is recoverable.

## Verify

```sh
./test.sh
```

The test builds from scratch in an isolated HOME, stresses concurrent updates,
installs twice, uninstalls, and checks that unknown hooks and settings survive.

## Adding another host

Hosts are compile-time adapters: one descriptor defines its name, settings file,
bundle ID, and hook events; one adapter translates those events into the shared
state model. The companion UI and hook installer read the same registry, so a
new host does not require another pet or another state store.

## Current limitations

- Release builds are universal and do not require Xcode. A warning-free first
  launch still requires a Developer ID signature and Apple notarization.
- Clicking Ronaldinho focuses the exact originating application. In the expanded
  match center, each host row is independently clickable. Exact terminal tabs are
  not exposed by host hooks, so focus stops at the application.

## License

The code is available under the [MIT License](LICENSE). The bundled Ronaldinho
sprite is redistributed with permission; see [ASSET_NOTICE.md](ASSET_NOTICE.md).

See [EXECUTION_PLAN.md](EXECUTION_PLAN.md) for the reviewed implementation plan.
