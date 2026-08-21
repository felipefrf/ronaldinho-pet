# Ronaldinho Pet

A small macOS companion for Claude Code, Claude Desktop, Codex CLI, and Codex
App. It uses native hooks and keeps one state file per session, so concurrent
terminals do not overwrite each other.

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
  choose **Pet size → Small / Medium / Large**, or scroll anywhere over the
  companion for continuous sizing. This choice is persisted.

The compact bar always shows Claude and Codex independently, including active
and finished counts. Click it to expand the fixed row for each host.

The installer:

- builds locally for the current Mac;
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

```sh
./uninstall.sh
```

Owned hooks are removed exactly; unrelated settings remain. The app, state, and
native Codex pet are moved to Trash so removal is recoverable.

## Verify

```sh
./test.sh
```

The test builds from scratch in an isolated HOME, stresses concurrent updates,
installs twice, uninstalls, and checks that unknown hooks and settings survive.

## Current limitations

- Source installation requires Xcode Command Line Tools. A true one-click release
  requires a universal, signed, notarized build.
- Clicking Ronaldinho focuses the exact originating application. In the expanded
  match center, each host row is independently clickable. Exact terminal tabs are
  not exposed by host hooks, so focus stops at the application.

## License

The code is available under the [MIT License](LICENSE). The bundled Ronaldinho
sprite is redistributed with permission; see [ASSET_NOTICE.md](ASSET_NOTICE.md).

See [EXECUTION_PLAN.md](EXECUTION_PLAN.md) for the reviewed implementation plan.
