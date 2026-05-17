# Modern Tilix — developer notes

This file supplements [README.md](README.md) with implementation-focused details.

## Module layout

| Path | Role |
|------|------|
| `source/gx/tilix/modern/store.d` | Load/save `~/.config/tilix/modern.json` |
| `source/gx/tilix/modern/quickbar.d` | Quick bar UI |
| `source/gx/tilix/modern/aichat.d` | AI chat dialog |
| `source/gx/tilix/modern/llm.d` | HTTP via `curl`, provider checks |
| `source/gx/tilix/modern/prefpage.d` | Preferences → Modern page |

Wiring: `appwindow.d`, `prefeditor/prefdialog.d`, `meson.build` (target `moderntilix`).

## Data file

`~/.config/tilix/modern.json` — quick commands, bash snippets, SSH hosts, AI prompts/chats, API settings.

## Build

Same as root [README.md](README.md). Wrapper script: `scripts/build-moderntilix.sh`.

## Not in repo

The `example/` directory (if present locally) is a private working tree and is ignored by git.
