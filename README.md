# Aiterm

Linux tiling terminal emulator (GTK+ 3 / VTE) with a productivity layer: quick commands, bash cheat sheet, SSH shortcuts, and OpenAI-compatible AI chat.

## Features

| Feature | Description |
|---------|-------------|
| Quick commands bar | Categories with popover menus; inserts text into the active terminal |
| Bash cheat sheet | Default snippets (`ip`, `ss`, `ls`, …) |
| SSH host list | Hosts from config → builds `ssh` command |
| AI chat | OpenAI-compatible API via `curl`; **Preferences → Modern** |
| AI prompt templates | Menus on the quick bar |
| AI agent mode | Runs fenced `bash` blocks in the active terminal |
| AI settings | Provider, base URL, model, API key, persist chats, agent toggle |

## Build and run

```bash
git clone git@github.com:mykola-riabov/ai_term.git
cd ai_term
./scripts/build-aiterm.sh
./scripts/run-aiterm.sh
```

`run-aiterm.sh` stages gresource, color schemes, and GSettings from the build tree. Do not run `./build/aiterm` directly unless the app is installed.

### Dependencies (Debian/Ubuntu)

```bash
sudo apt install ldc meson ninja-build \
  libgtkd-3-dev libvted-3-dev libgtk-3-dev libvte-2.91-dev \
  libglib2.0-dev libcairo2-dev libpango1.0-dev libx11-dev \
  libsecret-1-dev gettext appstream curl
```

### System install (optional)

```bash
meson install -C build
~/.local/bin/aiterm
```

## Configuration

`~/.config/aiterm/modern.json` — quick commands, snippets, SSH hosts, AI prompts/chats, API settings.

Application ID: `com.aiterm.Aiterm`

## UI

- **Quick bar** under the header (quick commands, cheat sheet, SSH, AI prompts, **AI** button)
- **Preferences → Modern** — AI provider configuration

## Local development

An optional working tree may exist under `example/` (gitignored, not published).

---

**Note:** Aiterm is based on a modified fork of [Tilix](https://github.com/gnunn1/tilix) (tiling GTK terminal for Linux). The upstream project provided the terminal core; this repository adds the Modern layer and rebrands the application as **Aiterm**.
