# VoxTyper on Nobara (KDE Plasma, Wayland)

This is the step-by-step walkthrough for Nobara and other Fedora-family distributions running KDE Plasma on Wayland. It is the same pipeline described in the main README, narrowed to the choices that matter on this stack: `dnf` for packages, `parecord` for audio capture, `wl-copy` for the clipboard, `wtype` for typing (with `ydotool` as a fallback), and a KDE Custom Shortcut to fire the script.

The main README in the repo root covers the cross-distro story; this file is intentionally Nobara-centric.

## 1. Helper packages

You can either let the installer do it for you (it detects Nobara via `ID_LIKE=fedora` and uses `dnf`):

```bash
chmod +x install-voxtyper.sh
./install-voxtyper.sh
```

Or install the same packages by hand:

```bash
sudo dnf install wl-clipboard wtype pulseaudio-utils alsa-utils libnotify
# optional, only if wtype does not work on your setup:
sudo dnf install ydotool
```

What each one is for:

- `wl-clipboard` provides `wl-copy` and `wl-paste`. The script uses `wl-copy` on Wayland sessions.
- `wtype` is a virtual-keyboard tool that speaks the Wayland protocol directly. It needs no daemon and no `/dev/uinput` permissions, which makes it the cleanest typing option on KDE Plasma 6 / Wayland.
- `pulseaudio-utils` provides `parecord`, the recorder the script prefers because it captures at 16 kHz mono natively (the rate Whisper actually wants).
- `alsa-utils` provides `arecord`, which the script falls back to if neither `parecord` nor `pw-record` are present.
- `libnotify` provides `notify-send`, used for the on-screen notifications.
- `ydotool` is the older Wayland typing tool. The script only falls back to it when `wtype` is missing; it needs `/dev/uinput` access and the `ydotoold` daemon to work.

The installer does not install `whisper-cpp` from the Fedora repositories. The Fedora package brings in a sizeable ROCm/CUDA dependency chain and on machines that already have a ROCm install it has been seen to downgrade parts of that stack. Building `whisper.cpp` yourself is much smaller and side-effect free.

## 2. Build whisper.cpp

```bash
cd ~/dev   # or wherever you keep source trees
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"

mkdir -p ~/.local/bin
cp build/bin/whisper-cli ~/.local/bin/whisper-cli
```

After this, `whisper-cli --help` should print usage and `voxtyper.sh` will find it through `PATH`.

If you would rather have the installer do this for you, run `./install-voxtyper.sh --build-whisper`. It runs the same commands and requires `git`, `cmake`, `make`, and `g++` to be installed first.

## 3. Whisper model

The default model in the script is the multilingual base, which is a good balance between accuracy and speed for dictation:

```bash
mkdir -p ~/.local/share/whisper
cd ~/.local/share/whisper
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

If your CPU has the headroom and you want better word accuracy, swap to `ggml-small.bin`, `ggml-medium.bin`, or `ggml-large.bin`, drop it in the same folder, and edit the `MODEL=` line in `voxtyper.sh` to point at the new filename.

## 4. Enable ydotoold (only if you skipped `wtype`)

If you installed `wtype`, skip this step. The script tries `wtype` first and only falls through to `ydotool` if `wtype` is missing or refuses the focused window's input.

If you are relying on `ydotool`, it needs the `ydotoold` daemon running and able to open `/dev/uinput`. Enable it once:

```bash
sudo systemctl enable --now ydotoold.service
```

If neither typing tool ends up working, the transcript is still copied to the clipboard. You just have to paste it manually with `Ctrl+V`.

## 5. Install the script

If you ran `./install-voxtyper.sh` without `--no-script`, the script is already at `~/.local/bin/voxtyper`. Otherwise:

```bash
mkdir -p ~/.local/bin
cp ./voxtyper.sh ~/.local/bin/voxtyper
chmod +x ~/.local/bin/voxtyper
```

If your Whisper binary is named something other than `whisper-cli`, either change the `WHISPER_BIN` line inside the script, or invoke it with `WHISPER_BIN=your-binary voxtyper` while testing.

## 6. Bind a shortcut in KDE Plasma

1. Open `System Settings` -> `Shortcuts` -> `Custom Shortcuts`.
2. Add a new entry of type `Command/URL`. Name it `VoxTyper`.
3. Set the trigger to the key combination you want, for example `Meta + X`.
4. Set the command to `~/.local/bin/voxtyper`.
5. Apply.

Press the shortcut once to start recording. Press it again to stop, transcribe, and have the text appear in whatever window is focused.

## 7. Behavior in detail

- First press
  - `notify-send` shows "Now listening for VoxTyper".
  - The script picks the first available recorder in this order: `parecord` (PulseAudio, the preferred path on a stock Nobara), then `pw-record` (PipeWire), then `arecord` (ALSA). The chosen recorder writes 16 kHz mono WAV to `$XDG_RUNTIME_DIR/voxtyper-record.wav`. The recorder PID and a start timestamp go into `$XDG_RUNTIME_DIR/voxtyper.state` so the second press knows what to stop.
- Second press
  - The script reads the state file. If less than two seconds have passed since the first press, it treats this as a spurious KDE key-up event and ignores it. Otherwise it signals the recorder with `SIGINT` so the WAV header is finalised.
  - `notify-send` shows "Stopped VoxTyper — transcribing...".
  - `whisper-cli -m ~/.local/share/whisper/ggml-base.bin -f $XDG_RUNTIME_DIR/voxtyper-record.wav -otxt -of $XDG_RUNTIME_DIR/voxtyper-output --language auto` runs. Output goes to `$XDG_RUNTIME_DIR/voxtyper-output.txt`.
  - The text is collapsed to a single line, copied to the clipboard, and typed into the active window via `wtype` (preferred), then `xdotool` (X11), then `ydotool` (Wayland fallback). The clipboard is populated even if typing succeeds.
  - The WAV and the transcript text file are deleted.

State and lock files in `$XDG_RUNTIME_DIR` keep the script safe under rapid presses: a PID-file mutex serialises invocations and the timestamped state file rejects KDE's spurious key-up events. A per-invocation debug log lands in `$XDG_RUNTIME_DIR/voxtyper-debug.log` for troubleshooting.

## 8. Quick test checklist

Run these one at a time and confirm each works before relying on the shortcut.

```bash
# Microphone — the recorder the script will actually use
parecord --channels=1 --rate=16000 /tmp/test.wav &
sleep 3 && kill -INT %1
aplay /tmp/test.wav

# Whisper
whisper-cli -m ~/.local/share/whisper/ggml-base.bin -f /tmp/test.wav -otxt -of /tmp/test
cat /tmp/test.txt

# Clipboard
echo "clipboard test" | wl-copy
wl-paste

# Typing (with a text field focused)
wtype 'hello from wtype'
# or, if you skipped wtype and rely on ydotool:
systemctl status ydotoold.service
ydotool type 'hello from ydotool'
```

If those pass, the Custom Shortcut should produce the same result end to end.

## 9. Troubleshooting

- Notification appears but no transcription. Check that `whisper-cli` is on `PATH`, that the model path in the script matches the file you downloaded, and look at `$XDG_RUNTIME_DIR/voxtyper-debug.log` for the whisper-cli output.
- Transcription works but nothing is typed. The clipboard still gets the text, so `Ctrl+V` is the workaround. Check the debug log to see which typing tool was tried and why it failed. Some applications (password fields, certain Electron apps) refuse synthetic input regardless of which tool you use.
- Recording starts but the second press does nothing. The toggle is driven by `$XDG_RUNTIME_DIR/voxtyper.state` and `$XDG_RUNTIME_DIR/voxtyper.lock`. If a previous run crashed, those can be left behind; remove them and try again. If the debug log shows a "Debounce" entry on every press, your shortcut is firing twice (KDE key-down + key-up) — increase `DEBOUNCE_SECONDS` at the top of `voxtyper.sh`.
- The script works from a terminal but not from the KDE shortcut. The script already sets its own `PATH`, but if you have placed the tools in an unusual location, prepend it to the `PATH` export at the top of `voxtyper.sh`.
