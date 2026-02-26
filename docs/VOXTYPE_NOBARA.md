## Offline Voxtype‑style Dictation on Nobara (KDE Plasma / Wayland)

This guide adapts the Arch + Hyprland workflow from your article to **Nobara / Fedora KDE (KWin Wayland)**.

It gives you:

- **Push‑to‑talk dictation** using `whisper.cpp` (via `whisper-cli`)
- **Offline transcription** with the multilingual `ggml-base.bin` model (`--language auto`)
- **Automatic paste** into the active window via `ydotool` (if configured)
- **Clipboard copy** fallback so you can always `Ctrl+V` the result

The repo also contains a ready script at the project root: `voxtyper.sh`, and an **installer** that detects your distro and installs the right packages: `install-voxtyper.sh`.

---

## 1. Install Required Packages

### Option A: Use the installer script (any supported distro)

From the project root:

```bash
chmod +x install-voxtyper.sh
./install-voxtyper.sh
```

This detects your distribution by reading `/etc/os-release` (using `ID` and `ID_LIKE`) and then installs the correct package names.
If it does not recognize your `ID`, it will try to guess a family from the available package manager (`dnf`, `apt`, `pacman`, `zypper`) instead.

Supported families out of the box include (examples, not exhaustive):

- **Fedora / Nobara / RHEL family**: `whisper-cpp`, `wl-clipboard`, `alsa-utils`, `libnotify`, `ydotool`
- **Debian / Ubuntu and derivatives** (incl. PikaOS, Linux Mint, Pop!_OS, etc.): `whisper.cpp`, `wl-clipboard`, `alsa-utils`, `libnotify-bin`, `ydotool`
- **Arch-based** (Arch, CachyOS, EndeavourOS, Manjaro, Garuda, ArcoLinux, Omarchy, etc.): `wl-clipboard`, `alsa-utils`, `libnotify`, `ydotool` from official repos; `whisper.cpp` from AUR (uses `paru` or `yay` if available)
- **openSUSE** (Tumbleweed, Leap, MicroOS): `wl-clipboard`, `alsa-utils`, `libnotify`, `ydotool` (Whisper may require manual install)
- **Void Linux**: `alsa-utils`, `libnotify`, `ydotool`, and optionally `wl-clipboard` if present in the repo
- **Alpine Linux**: `wl-clipboard`, `alsa-utils`, `libnotify`, and optionally `dotool` as a rough `ydotool` alternative
- **Gentoo**: `gui-apps/wl-clipboard`, `media-sound/alsa-utils`, `x11-libs/libnotify`, `x11-misc/ydotool`
- **NixOS**: prints a `configuration.nix` snippet with `openai-whisper-cpp`, `wl-clipboard`, `alsa-utils`, `libnotify`, `ydotool` instead of installing packages directly

Options:

- `./install-voxtyper.sh --no-script` — install packages only, do not copy `voxtyper.sh` to `~/.local/bin/voxtyper`
- `./install-voxtyper.sh --dry-run` — print what would be run, without installing

### Option B: Manual install (Nobara / Fedora)

On Nobara / Fedora, install the needed tools:

```bash
sudo dnf install whisper-cpp wl-clipboard alsa-utils libnotify ydotool
```

- **whisper-cpp**: Whisper speech‑to‑text (`whisper-cli` binary)
- **wl-clipboard**: `wl-copy` / `wl-paste` for Wayland clipboard
- **alsa-utils**: `arecord` for capturing microphone audio
- **libnotify**: `notify-send` desktop notifications
- **ydotool**: Xdotool‑style typing on Wayland using `/dev/uinput`

> If your Whisper binary isn’t named `whisper-cli`, you can override it later via the `WHISPER_BIN` environment variable in the script.

---

## 2. Download the Whisper Model

Use the **multilingual** base model (works with `--language auto`):

```bash
mkdir -p ~/.local/share/whisper
cd ~/.local/share/whisper
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

This is roughly equivalent to your article’s second post but uses the language‑agnostic model so both English and Greek work.

If you have a **stronger CPU/GPU** and want better accuracy (slower but higher quality), you can also download a larger model, for example:

- `ggml-small.bin`
- `ggml-medium.bin`
- `ggml-large.bin`

After downloading a bigger model into the same folder, update the `MODEL=` line in the script to point to it (e.g. `ggml-small.bin` instead of `ggml-base.bin`).

---

## 3. Enable `ydotoold` (Optional but Recommended)

`ydotool` requires the `ydotoold` daemon to be running and to have access to `/dev/uinput`.  
Enable it as a system service:

```bash
sudo systemctl enable --now ydotoold.service
```

If `ydotoold` is not running, the script will still:

- Record and transcribe
- Copy the result to the clipboard via `wl-copy`

But it **won’t type directly** into the active window; you’ll paste manually with `Ctrl+V`.

---

## 4. Script: `voxtyper.sh`

This repo contains the script at the project root: `voxtyper.sh`.  
To install it as `~/.local/bin/voxtyper` (as in your original guide):

```bash
mkdir -p ~/.local/bin
cp ./voxtyper.sh ~/.local/bin/voxtyper
chmod +x ~/.local/bin/voxtyper
```

(The installer script does this automatically unless you pass `--no-script`.)

If your Whisper executable is not `whisper-cli`, either:

- Edit the `WHISPER_BIN` line in the script, **or**
- Run it with `WHISPER_BIN=your-binary-name voxtyper` for testing, then bake that into the script.

---

## 5. KDE Plasma Global Shortcut

In KDE Plasma (Wayland):

1. Open **System Settings → Shortcuts → Custom Shortcuts**.
2. Add a new **Command/URL** action, name it e.g. **VoxTyper Dictation**.
3. Set the **trigger** you like (e.g. `Meta + X`).
4. Set the **command** to:

   ```bash
   ~/.local/bin/voxtyper
   ```

5. Apply the changes.

---

## 6. How It Works (Behavior)

- **First keypress** (e.g. `Meta + X`):
  - Shows a notification “Recording…”
  - Starts `arecord` in the background, mono (`-c 1`), saving to `/tmp/whisper-record.wav`

- **Second keypress**:
  - Stops `arecord` via `pkill -INT arecord`
  - Shows “Processing…” notification
  - Runs `whisper-cli` with:
    - Model: `~/.local/share/whisper/ggml-base.bin`
    - Input: `/tmp/whisper-record.wav`
    - Output: `/tmp/whisper-output.txt`
    - `--language auto` (auto‑detect language)
  - Normalises whitespace and:
    - Copies the text to Wayland clipboard via `wl-copy`
    - If `ydotool` is available and `ydotoold` is running, types the text into the active window with `ydotool type`

Temporary files in `/tmp` are cleaned up at the end of the cycle.

---

## 7. Quick Test Checklist

1. **Microphone**:
   ```bash
   arecord -f cd -c 1 -t wav /tmp/test.wav
   aplay /tmp/test.wav
   ```
2. **Whisper CLI**:
   ```bash
   whisper-cli -m ~/.local/share/whisper/ggml-base.bin -f /tmp/test.wav -otxt -of /tmp/test
   cat /tmp/test.txt
   ```
3. **Clipboard**:
   ```bash
   echo "Clipboard test" | wl-copy
   wl-paste
   ```
4. **ydotool**:
   - Make sure:
     ```bash
     systemctl status ydotoold.service
     ```
   - With a text field focused, run:
     ```bash
     ydotool type 'Hello from ydotool'
     ```

If all of these work, your Voxtype‑style dictation should behave like in the original Arch + Hyprland guide but adapted to Nobara KDE.

