# Modern Tilix (ai_term)

Fork of [Tilix](https://github.com/gnunn1/tilix) with productivity features inspired by **Win Tileterm**: quick commands, bash cheat sheet, SSH shortcuts, and OpenAI-compatible AI chat integrated into the terminal UI.

Upstream Tilix is a tiling GTK+ 3 terminal emulator for Linux. This fork adds a **Modern** layer (`source/gx/tilix/modern/`) while keeping Tilix sessions, profiles, and color schemes.

## Features

| Feature | Description |
|---------|-------------|
| Quick commands bar | Categories with popover menus; inserts text into the active VTE |
| Bash cheat sheet | Default snippets (`ip`, `ss`, `ls`, …) |
| SSH host list | Hosts from config → builds `ssh` command |
| AI chat | OpenAI-compatible API via `curl`; **Preferences → Modern** |
| AI prompt templates | Menus on the quick bar |
| AI agent mode | Runs ` ```bash ` fenced blocks in the active terminal |
| AI settings | Provider, base URL, model, API key, persist chats, agent toggle |

Not ported from the Windows prototype: CMD/PowerShell switching, custom Win UI themes, portable `.exe` builds, Electron stack.

## Configuration

Settings are stored in:

`~/.config/tilix/modern.json`

Includes quick commands, bash snippets, SSH hosts, AI prompts/chats, and API settings. API keys stay on your machine; do not commit this file.

## Build (Linux)

### System packages (Ubuntu/Debian)

```bash
sudo apt install ldc meson ninja-build \
  libgtkd-3-dev libvted-3-dev libgtk-3-dev libvte-2.91-dev \
  libglib2.0-dev libcairo2-dev libpango1.0-dev libx11-dev \
  libsecret-1-dev gettext appstream curl

git clone git@github.com:mykola-riabov/ai_term.git
cd ai_term
source ~/dlang/ldc-*/activate   # if using install.sh LDC
meson setup build --prefix="$HOME/.local"
meson compile -C build
./build/moderntilix
```

### Without sudo (local sysroot)

```bash
./scripts/build-moderntilix.sh
./build/moderntilix
```

Requires `curl` for AI requests.

## UI

- **Quick bar** under the header (quick commands, cheat sheet, SSH, AI prompts, **AI** button).
- **Preferences → Modern** — AI provider configuration.

## Local development copy

A full tree may exist under `example/` for local experiments. That directory is listed in `.gitignore` and is **not** pushed to GitHub.

## Status

Core modules and UI wiring are in place. Hub modals for editing quick commands/snippets (from the Windows prototype) are not ported yet — edit `modern.json` or extend `source/gx/tilix/modern/`.

## License

[MPL-2.0](LICENSE) — same as upstream Tilix. See [CREDITS.md](CREDITS.md) for attribution.

## Upstream

- [Tilix](https://github.com/gnunn1/tilix)
- [Tilix documentation](https://gnunn1.github.io/tilix-web)

More build and migration notes from upstream remain in the original Tilix README sections; prefer **meson** and target `moderntilix` for this fork.
