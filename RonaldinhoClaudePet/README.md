# Ronaldinho companion for Claude Code

This small macOS companion window animates the Ronaldinho sprite sheet beside your terminal. Claude Code hooks update its state through `~/.claude/ronaldinho-pet/state.json`.

States used by the supplied hook configuration:

- `idle`: the smooth Six Seven loop
- `running`: after a prompt and while tools run
- `waiting`: when Claude Code needs permission or input

Interaction controls:

- Click Ronaldinho to bring the terminal app from the most recent Claude Code hook to the foreground.
- Drag him left or right to use the matching directional running animation.
- Hover over him to trigger the jumping animation.
- The small handle beneath him is tucked away by default. Green means Claude has finished and the result is still unseen; after you click Ronaldinho or open the handle, it becomes subtle and transparent. Click it to expand a translucent status message. Input requests open it automatically.
- Right-click him to reset his position or quit it.

The companion renders at a deliberately relaxed 6 FPS so the idle Six Seven move remains readable.

In Claude Code, run `/pet` to show Ronaldinho again if the companion is hidden. The personal command is installed at `~/.claude/commands/pet.md`.

Build with:

```zsh
./build-app.sh /absolute/path/to/spritesheet.webp
```

Launch with:

```zsh
open RonaldinhoClaudePet.app
```

## Install on another Mac

The portable installer rebuilds the app for the target Mac, so it works on either Apple Silicon or Intel hardware. It requires macOS, Claude Code, and Xcode Command Line Tools.

1. Copy the installer folder (or the packaged ZIP) to the other Mac.
2. In Terminal, open that folder and run `./install.sh`.
3. Restart Claude Code, then run `/pet` whenever you want Ronaldinho to appear.

The installer places everything under `~/.claude/ronaldinho-pet`, creates the personal `/pet` command, and merges only Ronaldinho-related hooks into `~/.claude/settings.json`. It saves a timestamped backup of that settings file first.
