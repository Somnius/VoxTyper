# VoxTyper

Offline push-to-talk voice dictation for Linux. One shortcut starts recording, the same shortcut stops it, runs the audio through a local Whisper model, and writes the result into the focused window (and the clipboard as a backup).

Nothing leaves the machine. There is no account, no API key, no daemon beyond what your distro already ships with.

- Version: 0.5.0
- License: MIT (see `LICENSE`)
- Author: Lefteris @SomniusX

## What it does

`voxtyper.sh` is a single Bash script invoked by a keybinding. It works as a toggle:

1. First press. The script shows a "Now listening for VoxTyper" notification and launches the first available recorder (`parecord`, `pw-record`, or `arecord`) in the background, capturing 16 kHz mono WAV into `$XDG_RUNTIME_DIR/voxtyper-record.wav`. It records its own PID and the start timestamp into a state file in the same directory.
2. Second press. The script reads the state file, signals the recorder with `SIGINT`, then calls `whisper-cli` against `~/.local/share/whisper/ggml-base.bin` with `--language auto`. The transcript is collapsed to a single line, copied to the clipboard, and typed into the active window via `wtype`, `xdotool`, or `ydotool` (whichever resolves first). Temporary files are removed on the way out.

Tools are picked at runtime in the order shown in the Requirements table below. The clipboard is always populated, even if typing succeeds, so paste remains available as a backup. Two safety nets sit on top of the basic toggle: a PID-file mutex in `$XDG_RUNTIME_DIR` so two presses landing on top of each other cannot interleave, and a two-second debounce window that ignores a second invocation arriving immediately after the first (KDE Plasma sometimes fires global shortcuts on both press and release).

The script sets its own `PATH` (including `~/.local/bin`, Guix home, and `/run/current-system/profile/bin`) so it runs identically from a desktop-environment shortcut, a terminal, or a window-manager keybind, without needing a login shell.

## What it is not

- Not a continuous transcriber. Recording is bounded by your two key presses.
- Not a model. You bring your own Whisper `.bin` file.
- Not a wrapper around a cloud API. The pipeline is recorder -> `whisper-cli` -> typing tool / clipboard.
- Not a GUI. Configuration is done by editing the script or exporting `WHISPER_BIN`.

## Requirements

The script picks the first available tool in each category at runtime, so you only need one entry from each row to be installed. Preferred options are listed first.

| Purpose         | Preferred                              | Fallbacks                                          | Notes                                                                                  |
|-----------------|----------------------------------------|----------------------------------------------------|----------------------------------------------------------------------------------------|
| Audio capture   | `parecord` (PulseAudio)                | `pw-record` (PipeWire), then `arecord` (ALSA)      | All three are recorded at 16 kHz mono, the rate Whisper resamples to anyway.            |
| Typing          | `wtype` (Wayland virtual keyboard)     | `xdotool` (X11), then `ydotool` (Wayland w/ daemon) | `wtype` needs no daemon and no `/dev/uinput` permissions, so it is the cleanest option. |
| Clipboard       | `wl-copy` (Wayland)                    | `xclip` (X11)                                       | Clipboard is always populated as a backup, even if typing succeeds.                     |
| Notifications   | `notify-send`                          | (none — script falls back to stdout)                | From `libnotify` / `libnotify-bin`.                                                     |
| Transcription   | `whisper-cli`                          | Override via `WHISPER_BIN=...`                      | Built from `whisper.cpp`.                                                               |

The Whisper binary can be renamed by setting `WHISPER_BIN` in the environment. The model path is hardcoded to `~/.local/share/whisper/ggml-base.bin`; change the `MODEL` variable at the top of the script to point elsewhere.

## Install

### 1. Helper tools

From the repo root:

```bash
chmod +x install-voxtyper.sh
./install-voxtyper.sh
```

The installer reads `/etc/os-release` (`ID` and `ID_LIKE`), picks a distribution family, and installs only the helper packages. It deliberately does not install the distro `whisper-cpp` package; see the next section for why.

Families it recognises:

- Fedora, Nobara, RHEL, Rocky, Alma, CentOS Stream
- Debian, Ubuntu, Linux Mint, Pop!\_OS, PikaOS, Zorin, KDE Neon, elementary, Kali, MX
- Arch, CachyOS, EndeavourOS, Manjaro, Garuda, ArcoLinux, Omarchy
- openSUSE Tumbleweed, Leap, MicroOS
- Void, Alpine, Gentoo
- NixOS (prints a configuration snippet instead of installing)

If the `ID` is unknown, the installer falls back to whichever package manager it finds (`dnf`, `apt`, `pacman`, `zypper`) and uses the matching family. If none of those exist it prints the manual package list and exits.

Flags:

- `--no-script` install packages only; do not copy `voxtyper.sh` to `~/.local/bin/voxtyper`.
- `--dry-run` print the commands that would run.
- `--build-whisper` after the package step, clone and build `whisper.cpp` from source into `~/dev/whisper.cpp` (override with `WHISPER_SRC_DIR`) and copy `whisper-cli` to `~/.local/bin`. Requires `git`, `cmake`, `make`, and `g++`.

Guix System is intentionally not handled by the installer. Add the packages declaratively in `~/.config/guix/home.scm`:

```
"alsa-utils" "alsa-plugins:pulseaudio" "xclip" "xdotool"
```

then run `guix home reconfigure`. `libnotify` usually comes in via `%desktop-services`.

For the full Guix System story (why the script has a `/gnu/store` fallback, how to build `whisper.cpp` inside `guix shell`, the `wget`/TLS workaround), see [`docs/GUIX.md`](docs/GUIX.md). For the NixOS equivalent (declaring helpers in `configuration.nix`, `programs.ydotool.enable`, building inside `nix-shell`), see [`docs/NIXOS.md`](docs/NIXOS.md). [`docs/NIXOS.md`](docs/NIXOS.md) also has a "Going fully declarative" section that documents the NixOS-only path: packaging `voxtyper` with `pkgs.writeShellScriptBin`, pinning the model via `pkgs.fetchurl`, and wiring the KDE keybind through `plasma-manager`. A focused Fedora/Nobara walkthrough is in [`docs/NOBARA.md`](docs/NOBARA.md).

### 2. whisper.cpp

The README used to suggest `dnf install whisper-cpp` and the equivalents on other distros. We no longer recommend that. On several distributions the package pulls in CUDA, ROCm, OpenVINO, or large `proj-data-*` GIS tables, and on at least one (Fedora-family with ROCm installed) it has been reported to downgrade the existing ROCm stack. Building from source avoids all of that:

```bash
cd ~/dev   # or anywhere
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
mkdir -p ~/.local/bin
cp build/bin/whisper-cli ~/.local/bin/whisper-cli
```

On Guix System, build inside a `guix shell` so the binary links against Guix's glibc:

```bash
guix shell gcc-toolchain cmake make -- bash -c "
  cd ~/dev/whisper.cpp && \
  rm -rf build && \
  cmake -B build -DCMAKE_BUILD_TYPE=Release && \
  cmake --build build -j\$(nproc) && \
  cp build/bin/whisper-cli ~/.local/bin/whisper-cli
"
```

### 3. Model

The default model is `ggml-base.bin`, the multilingual base. It is small enough to transcribe in near real time on a modern CPU and works well enough for dictation in English plus most major European languages.

```bash
mkdir -p ~/.local/share/whisper
cd ~/.local/share/whisper
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

If `wget` complains about certificates on Guix, use `curl` with the system CA bundle:

```bash
curl --cacert /etc/ssl/certs/ca-certificates.crt \
  -L -o ~/.local/share/whisper/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

For better accuracy at the cost of latency, swap in `ggml-small.bin`, `ggml-medium.bin`, or `ggml-large.bin` and update the `MODEL=` line in the script.

### 4. Keybinding

The installer drops the script at `~/.local/bin/voxtyper`. Bind that path to a shortcut in your desktop environment or compositor. A few examples:

- KDE Plasma: System Settings -> Shortcuts -> Custom Shortcuts -> Command/URL.
- GNOME: Settings -> Keyboard -> Custom Shortcuts.
- XFCE: Settings -> Keyboard -> Application Shortcuts.
- Hyprland, Sway, river, niri: a `bind` line in the compositor config pointing at `~/.local/bin/voxtyper`.

If you use `ydotool`, enable the daemon once: `sudo systemctl enable --now ydotoold.service`. Without it, transcription still happens and the text still lands on the clipboard; you just have to paste manually.

## Sanity check

```bash
whisper-cli --help | head -3
arecord -f cd -c 1 -t wav /tmp/t.wav -d 3
whisper-cli -m ~/.local/share/whisper/ggml-base.bin -f /tmp/t.wav -otxt -of /tmp/t
cat /tmp/t.txt
```

If those four commands produce the expected output, the keybinding should work end to end.

## Configuration knobs

There are very few. All of them live near the top of `voxtyper.sh`:

- `MODEL` path to the `.bin` model.
- `WHISPER_BIN` name of the Whisper executable (defaults to `whisper-cli`; can be overridden from the environment).
- `RUNTIME_DIR` where recordings, transcripts, the PID lock, the state file, and the debug log are kept. Defaults to `$XDG_RUNTIME_DIR` (typically a tmpfs cleaned at logout) with a fall back to `~/.cache/voxtyper`.
- `DEBOUNCE_SECONDS` how long after the start of a recording any second invocation is treated as a spurious key-up event. Defaults to `2`; KDE Plasma is the main reason this exists.
- `PATH` export at the top of the file. Adjust if your tools live somewhere unusual.

The recording format is 16 kHz mono, 16-bit WAV — the rate Whisper actually wants — so there is no resampling at transcription time. The script picks the first available recorder among `parecord` (PulseAudio), `pw-record` (PipeWire), and `arecord` (ALSA).

## Version history

- 0.1.0 First release. Arch + Hyprland. Posted as a guide on linux-user.gr.
- 0.2.0 First public repo. Nobara / KDE focus.
- 0.2.2 Multi-distro installer, `/etc/os-release`-driven detection, separate Nobara guide moved to `docs/`.
- 0.3.0 Stopped recommending distro `whisper-cpp` packages. Switched the documentation to source builds.
- 0.3.1 `--build-whisper` flag in the installer for an automated source build.
- 0.4.0 X11 support with `xclip`/`xdotool` as the preferred tools and the Wayland pair as fallback; Guix System notes; self-contained `PATH` so the script works from desktop shortcuts; updated notification text.
- 0.5.0 Audio capture chain (`parecord` -> `pw-record` -> `arecord`) at native 16 kHz mono; `wtype` added as the preferred Wayland typing tool ahead of `ydotool`; runtime state moved from `/tmp` into `$XDG_RUNTIME_DIR` with a `~/.cache` fallback; PID-file mutex to serialize concurrent presses; KDE Plasma key-up debounce; per-invocation debug log under `$XDG_RUNTIME_DIR/voxtyper-debug.log`.

## Credits

The push-to-talk, type-into-the-active-field idea comes from VoxType in Omarchy (https://learn.omacom.io/2/the-omarchy-manual/107/ai). VoxTyper is an independent reimplementation on top of whisper.cpp and shares no code with Omarchy.

## License

The scripts in this repository are MIT-licensed (see `LICENSE`). whisper.cpp and the helper tools each carry their own licences, which apply when you install or build them.
