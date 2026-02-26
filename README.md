# VoxTyper

**Offline push-to-talk voice dictation for Linux** — no cloud, no account. Speak, then have the text typed into the focused window or copied to the clipboard.

- **Version:** 0.2.0 ([Semantic Versioning](https://semver.org/))
- **Supported:** Fedora/Nobara, Debian/Ubuntu, Arch, openSUSE (Wayland-friendly; works with KDE, Hyprland, and others where `ydotool` is available)

## Features

- Push-to-talk: one shortcut to start recording, same shortcut again to stop and transcribe
- Fully offline: [whisper.cpp](https://github.com/ggerganov/whisper.cpp) runs locally
- Multilingual: default model uses `--language auto` (e.g. English and Greek)
- Optional: type into focused window via `ydotool`, or just paste from clipboard

## Requirements

- `whisper.cpp` (or distro package: `whisper-cpp` / `whisper.cpp`)
- `wl-clipboard` (Wayland clipboard)
- `alsa-utils` (for `arecord`)
- `libnotify` or `libnotify-bin` (notifications)
- `ydotool` (for typing into the active window; optional if you only use clipboard)

## Quick start

1. **Install dependencies** (from project root):

   ```bash
   chmod +x install-voxtyper.sh
   ./install-voxtyper.sh
   ```

   This detects your distro and installs the right packages. Use `--no-script` to only install packages; use `--dry-run` to see what would run.

2. **Download a Whisper model** (e.g. multilingual base):

   ```bash
   mkdir -p ~/.local/share/whisper
   cd ~/.local/share/whisper
   wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
   ```

3. **Enable `ydotoold`** (for typing into the active window):

   ```bash
   sudo systemctl enable --now ydotoold.service
   ```

4. **Bind a shortcut** to `~/.local/bin/voxtyper` (e.g. Meta+X in KDE Shortcuts or your compositor config).

See [VOXTYPE_NOBARA.md](VOXTYPE_NOBARA.md) for a detailed guide (Nobara/KDE and other distros).

## Version history

- **0.1.0** — Initial release for Arch-based distros with Hyprland (see [original thread](https://linux-user.gr/t/odhgos-gia-offline-voxtype-style-dictation-se-arch-hyprland/6142)).
- **0.2.0** — Multi-distro installer, `voxtyper.sh` and `install-voxtyper.sh`; support for Fedora/Nobara, Debian/Ubuntu, Arch, openSUSE; KDE/Wayland focus.

## Credits and inspiration

VoxTyper was inspired by **VoxType** from [Omarchy](https://learn.omacom.io/2/the-omarchy-manual/107/ai) — the idea of push-to-talk, offline voice-to-text that types into the active field. This project is an independent implementation using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) and does not use any Omarchy or third-party dictation services.

## License

Scripts in this repository are provided as-is. You use whisper.cpp and other dependencies under their respective licenses (e.g. MIT for whisper.cpp).
