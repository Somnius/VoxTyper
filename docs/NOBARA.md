# VoxTyper on Nobara (KDE Plasma, Wayland)

This is the step-by-step walkthrough for Nobara and other Fedora-family distributions running KDE Plasma on Wayland. It is the same pipeline described in the main README, narrowed to the choices that matter on this stack: `dnf` for packages, `wl-copy` for the clipboard, `ydotool` for typing, and a KDE Custom Shortcut to fire the script.

The main README in the repo root covers the cross-distro story; this file is intentionally Nobara-centric.

## 1. Helper packages

You can either let the installer do it for you (it detects Nobara via `ID_LIKE=fedora` and uses `dnf`):

```bash
chmod +x install-voxtyper.sh
./install-voxtyper.sh
```

Or install the same packages by hand:

```bash
sudo dnf install wl-clipboard alsa-utils libnotify ydotool
```

What each one is for:

- `wl-clipboard` provides `wl-copy` and `wl-paste`. The script uses `wl-copy` on Wayland sessions.
- `alsa-utils` provides `arecord`, which captures the microphone to a WAV file.
- `libnotify` provides `notify-send`, used for the two on-screen notifications.
- `ydotool` is the Wayland equivalent of `xdotool`. It needs `/dev/uinput` and the `ydotoold` daemon to work.

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

## 4. Enable ydotoold

`ydotool` needs the `ydotoold` daemon running and able to open `/dev/uinput`. Enable it once:

```bash
sudo systemctl enable --now ydotoold.service
```

If the daemon is not running, transcription still works and the text is still copied to the clipboard. You just have to paste it manually with `Ctrl+V` instead of having it appear in the focused field.

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
  - `arecord -f cd -c 1 -t wav /tmp/whisper-record.wav` starts in the background. `cd` means 16-bit, 44.1 kHz; `-c 1` is mono.
- Second press
  - `pkill -INT arecord` stops the recorder cleanly so the WAV header is finalised.
  - `notify-send` shows "Stopped VoxTyper — transcribing...".
  - `whisper-cli -m ~/.local/share/whisper/ggml-base.bin -f /tmp/whisper-record.wav -otxt -of /tmp/whisper-output --language auto` runs. Output goes to `/tmp/whisper-output.txt`.
  - The text file is collapsed to a single line, copied to the clipboard, and typed into the active window.
  - `/tmp/whisper-record.wav` and `/tmp/whisper-output.txt` are deleted.

The script tries `xclip` before `wl-copy`, and `xdotool` before `ydotool`. On a pure Wayland Plasma session only the second tool in each pair will be present, so those are the ones that run.

## 8. Quick test checklist

Run these one at a time and confirm each works before relying on the shortcut.

```bash
# Microphone
arecord -f cd -c 1 -t wav /tmp/test.wav -d 3
aplay /tmp/test.wav

# Whisper
whisper-cli -m ~/.local/share/whisper/ggml-base.bin -f /tmp/test.wav -otxt -of /tmp/test
cat /tmp/test.txt

# Clipboard
echo "clipboard test" | wl-copy
wl-paste

# ydotool (with a text field focused)
systemctl status ydotoold.service
ydotool type 'hello from ydotool'
```

If all four pass, the Custom Shortcut should produce the same result end to end.

## 9. Troubleshooting

- Notification appears but no transcription. Check that `whisper-cli` is on `PATH` and that the model path in the script matches the file you downloaded.
- Transcription works but nothing is typed. `ydotoold` is probably not running, or your user is not in a group that can open `/dev/uinput`. The clipboard copy still happens, so `Ctrl+V` should give you the text.
- Recording starts but the second press does nothing. Make sure only one instance of `arecord` is running (`pgrep -x arecord`); the toggle relies on detecting it.
- The script works from a terminal but not from the KDE shortcut. The script already sets its own `PATH`, but if you have placed the tools in an unusual location, prepend it to the `PATH` export at the top of `voxtyper.sh`.
