# VoxTyper

**Offline push-to-talk voice dictation for Linux** — no cloud, no account. Speak, then have the text typed into the focused window or copied to the clipboard.

- **Version:** 0.3.1 ([Semantic Versioning](https://semver.org/))
- **Supported:** Fedora/Nobara/RHEL family, Debian/Ubuntu and derivatives (incl. PikaOS, Mint, Pop!_OS, etc.), Arch-based (Arch, CachyOS, EndeavourOS, Manjaro, Garuda, ArcoLinux, Omarchy, etc.), openSUSE, Void, Alpine, Gentoo, and NixOS (via installer logic; see below).

## Features

- Push-to-talk: one shortcut to start recording, same shortcut again to stop and transcribe
- Fully offline: [whisper.cpp](https://github.com/ggerganov/whisper.cpp) runs locally
- Multilingual: default model uses `--language auto` (e.g. English and Greek)
- Optional: type into focused window via `ydotool`, or just paste from clipboard

## Requirements

- `whisper.cpp` built from source (recommended)
  - We strongly discourage using distro `whisper-cpp` / `whisper.cpp` packages: on some distros they can pull in many gigabytes of GPU / GIS dependencies (CUDA, ROCm, OpenVINO, proj-data-*, etc.) or even downgrade your ROCm stack.
  - Instead, build `whisper-cli` from the official repository (see Quick start step 2).
- `wl-clipboard` (Wayland clipboard)
- `alsa-utils` (for `arecord`)
- `libnotify` or `libnotify-bin` (notifications)
- `ydotool` (for typing into the active window; optional if you only use clipboard)

## Quick start

1. **Install helper dependencies** (from project root):

   ```bash
   chmod +x install-voxtyper.sh
   ./install-voxtyper.sh
   ```

   This reads `/etc/os-release` (using `ID` and `ID_LIKE`) to detect your distro and install the right helper packages, and falls back to the available package manager (`dnf` / `apt` / `pacman` / `zypper`) if it sees an unknown ID.
   It knows about:

   - **Fedora / Nobara / RHEL family**
   - **Debian / Ubuntu and derivatives** (incl. PikaOS, Linux Mint, Pop!_OS, etc.)
   - **Arch-based** (Arch, CachyOS, EndeavourOS, Manjaro, Garuda, ArcoLinux, Omarchy, etc.)
   - **openSUSE** (Tumbleweed, Leap, MicroOS)
   - **Void Linux**
   - **Alpine Linux** (uses `dotool` as an optional `ydotool` alternative)
   - **Gentoo**
   - **NixOS** (prints a `configuration.nix` snippet instead of trying to install packages directly)

   Use `--no-script` to only install packages (skip copying `voxtyper.sh` to `~/.local/bin/voxtyper`), or `--dry-run` to see what would run without making changes.  
   You can also pass `--build-whisper` to let the installer try to clone and build `whisper.cpp` from source for you (using the same steps as below), if `git`/`cmake`/`make`/`g++` are available.

2. **Install whisper.cpp from source (recommended)**  
   This avoids distro `whisper-cpp` packages pulling in huge GPU/GIS stacks.

   ```bash
   cd ~/dev              # or wherever you keep source
   git clone https://github.com/ggerganov/whisper.cpp.git
   cd whisper.cpp

   cmake -B build -DCMAKE_BUILD_TYPE=Release
   cmake --build build -j"$(nproc)"

   mkdir -p ~/.local/bin
   cp build/bin/whisper-cli ~/.local/bin/whisper-cli
   ```

   After this, `whisper-cli --help` should work and `voxtyper.sh` will be able to find it.

3. **Download a Whisper model** (e.g. multilingual base):

   ```bash
   mkdir -p ~/.local/share/whisper
   cd ~/.local/share/whisper
   wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
   ```

4. **Enable `ydotoold`** (for typing into the active window):

   ```bash
   sudo systemctl enable --now ydotoold.service
   ```

5. **Bind a shortcut** to `~/.local/bin/voxtyper` (e.g. Meta+X in KDE Shortcuts or your compositor config).

See [`docs/VOXTYPE_NOBARA.md`](docs/VOXTYPE_NOBARA.md) for a detailed guide (Nobara/KDE and other distros).

## Version history

- **0.1.0** — Initial release for Arch-based distros with Hyprland (see [original thread](https://linux-user.gr/t/odhgos-gia-offline-voxtype-style-dictation-se-arch-hyprland/6142)).
- **0.2.0** — VoxTyper initial public repo release (Nobara/KDE focus).
- **0.2.2** — Extended multi-distro installer (`install-voxtyper.sh`), smarter `/etc/os-release` detection (PikaOS, CachyOS, Omarchy, etc.), and moved the detailed Nobara/KDE guide to `docs/VOXTYPE_NOBARA.md`.
- **0.3.0** — Stop auto-installing distro `whisper-cpp` packages; recommend building whisper.cpp from source instead; update installer messaging and docs accordingly.
- **0.3.1** — Add optional `--build-whisper` flag to the installer to clone/build whisper.cpp from source automatically when requested.

## Credits and inspiration

VoxTyper was inspired by **VoxType** from [Omarchy](https://learn.omacom.io/2/the-omarchy-manual/107/ai) — the idea of push-to-talk, offline voice-to-text that types into the active field. This project is an independent implementation using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) and does not use any Omarchy or third-party dictation services.

## License

Scripts in this repository are provided as-is. You use whisper.cpp and other dependencies under their respective licenses (e.g. MIT for whisper.cpp).
