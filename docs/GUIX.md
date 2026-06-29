# VoxTyper on Guix System

This is the full walkthrough for getting VoxTyper running on Guix System. It assumes a working Guix installation with a graphical session (GNOME, Plasma, XFCE, or a window manager that the `%desktop-services` set understands). The script targets X11 sessions on Guix; a note on Wayland is at the end.

Guix is unusual enough that several things in `voxtyper.sh` exist specifically to make it work here. This document explains both what to do and why those bits are there.

## Why Guix needs its own walkthrough

Three things are different from a typical distribution:

- **Packages are declared, not installed imperatively.** There is no `sudo dnf install` equivalent. You edit a configuration (system config, or `~/.config/guix/home.scm` for Guix Home), then reconfigure.
- **Binaries live under `/gnu/store/<hash>-<name>-<version>/`.** Every package is content-addressed by hash. Symlinks under profiles (`~/.guix-home/profile/bin`, `/run/current-system/profile/bin`) point into the store.
- **Binaries built outside Guix usually do not run.** The dynamic loader they were linked against does not exist on a Guix host, so a `whisper-cli` copied in from a Fedora machine will exit with a cryptic `No such file or directory` for the loader.

`voxtyper.sh` accommodates the first two by managing its own `PATH` and by carrying a fallback path for `notify-send`. The third is handled by always building `whisper.cpp` inside `guix shell` (see step 3).

## What you will end up with

- Helper tools (`xclip`, `xdotool`, `arecord`, `notify-send`) declared in `~/.config/guix/home.scm` and materialised by `guix home reconfigure`.
- `whisper-cli` built from source against Guix's toolchain, installed at `~/.local/bin/whisper-cli`.
- `ggml-base.bin` model under `~/.local/share/whisper/`.
- `voxtyper.sh` installed as `~/.local/bin/voxtyper`, bound to a key combination by your desktop environment.

## Step 1 — Declare the helper packages

Open `~/.config/guix/home.scm`. If you do not have a Guix Home configuration yet, create one. A minimal file that includes the VoxTyper helpers looks like this:

```scheme
(use-modules (gnu home)
             (gnu home services)
             (gnu packages)
             (guix gexp))

(home-environment
 (packages
  (specifications->packages
   (list "alsa-utils"
         "alsa-plugins:pulseaudio"
         "xclip"
         "xdotool"
         "libnotify"))))
```

What each package is doing:

- `alsa-utils` provides `arecord`, the microphone capture tool the script uses.
- `alsa-plugins:pulseaudio` is the ALSA-to-PulseAudio bridge. Without it, on a host where PulseAudio or PipeWire owns the audio device, `arecord` will fail to open `default` and the script will produce a zero-byte WAV.
- `xclip` provides the clipboard tool the script prefers on X11.
- `xdotool` provides the typing tool the script prefers on X11.
- `libnotify` provides `notify-send`. The script will also try a hard-coded `/gnu/store` path as a last resort, but the right approach is to have it on `PATH`.

Apply the configuration:

```bash
guix home reconfigure ~/.config/guix/home.scm
```

The first reconfigure can take a while (Guix builds or substitutes everything that is not already in your store). On subsequent runs it is fast.

Verify the tools resolved:

```bash
command -v arecord notify-send xclip xdotool
```

All four should print paths under `~/.guix-home/profile/bin/`. If `notify-send` is missing, double-check that `libnotify` is in the package list and that you reconfigured after editing.

## Step 2 — Optional: system-level helpers

If you would rather declare the helpers at the system level (so all users on the machine get them) rather than per user, add them to `environment.packages` or `operating-system` packages in your system config, then run `sudo guix system reconfigure /etc/config.scm`. Either approach works, because `voxtyper.sh` puts both the home profile and the system profile on its `PATH`.

The relevant line at the top of `voxtyper.sh` is:

```bash
export PATH="$HOME/.local/bin:$HOME/.guix-home/profile/bin:/run/current-system/profile/bin:/usr/sbin:/usr/bin:$PATH"
```

The home profile (`~/.guix-home/profile/bin`) and the system profile (`/run/current-system/profile/bin`) are both on the search path before any inherited `PATH`, so the script will find the tools no matter which profile you put them in.

## Step 3 — Build whisper.cpp inside `guix shell`

`whisper.cpp` is not in Guix's main channel as a normal user package, and even if you found a third-party channel for it the easier path is to build from source. The single critical thing is that the build must happen inside a `guix shell` so the resulting binary links against Guix's GCC and glibc.

```bash
mkdir -p ~/dev
cd ~/dev
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

guix shell gcc-toolchain cmake make -- bash -c "
  rm -rf build && \
  cmake -B build -DCMAKE_BUILD_TYPE=Release && \
  cmake --build build -j\$(nproc) && \
  mkdir -p \$HOME/.local/bin && \
  cp build/bin/whisper-cli \$HOME/.local/bin/whisper-cli
"
```

Notes on the command above:

- `rm -rf build` is intentional. If you previously built outside `guix shell`, CMake will have cached compiler paths that no longer exist inside the shell. Removing the build directory forces a fresh configure.
- `gcc-toolchain` (rather than just `gcc`) is what pulls in the linker, libc headers, and runtime that the resulting binary needs.
- `cmake` and `make` are the build tools.
- The script captures `~/.local/bin/whisper-cli` because that is the location VoxTyper's `PATH` prefers, and it survives `guix home reconfigure` (it is not managed by Guix).

Verify the binary works from outside the shell:

```bash
whisper-cli --help | head -3
```

If you get an error like `No such file or directory` referring to a loader path under `/lib64`, the build picked up your host toolchain instead of Guix's. Remove `build/`, re-enter `guix shell`, and rebuild.

## Step 4 — Download the Whisper model

The default model is the multilingual base. It is small enough to transcribe in near real time on a modern CPU.

```bash
mkdir -p ~/.local/share/whisper
cd ~/.local/share/whisper
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

If `wget` fails with a TLS certificate error, it is because the system CA bundle is not where `wget` looks by default on Guix. The simplest fix is to use `curl` and point it at the bundle explicitly:

```bash
curl --cacert /etc/ssl/certs/ca-certificates.crt \
  -L -o ~/.local/share/whisper/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

If `curl` itself is missing, add it to your `home.scm` package list (`"curl"`) and reconfigure.

Larger models give better accuracy at the cost of transcription latency. `ggml-small.bin`, `ggml-medium.bin`, and `ggml-large.bin` are all served from the same URL prefix. After downloading a different model, update the `MODEL=` line near the top of `voxtyper.sh`.

## Step 5 — Install the VoxTyper script

The installer script `install-voxtyper.sh` deliberately does not run on Guix; doing imperative package installs would be the wrong shape for the system. Copy the script in by hand:

```bash
mkdir -p ~/.local/bin
cp ./voxtyper.sh ~/.local/bin/voxtyper
chmod +x ~/.local/bin/voxtyper
```

Run it once from a terminal to confirm everything resolves:

```bash
voxtyper
# should show: "Now listening for VoxTyper"
voxtyper
# stops, transcribes (probably to an empty string on the first try), exits cleanly
```

If you see `VoxTyper: ...` printed to the terminal instead of a desktop notification, `notify-send` is not on `PATH`. Go back to step 1, confirm `libnotify` is in your `home.scm`, reconfigure, then re-run.

### About the `/gnu/store` notify-send fallback

The script contains this block:

```bash
NOTIFY_STORE="/gnu/store/zz1a4i2x6ahgyvs13pl2q5qg979f67ng-libnotify-0.8.8/bin/notify-send"
if command -v notify-send >/dev/null 2>&1; then
  NOTIFY_SEND="notify-send"
elif [[ -x "$NOTIFY_STORE" ]]; then
  NOTIFY_SEND="$NOTIFY_STORE"
fi
```

The intent is to keep working on a host that has `libnotify` pulled in by `%desktop-services` but not put on the user's `PATH`. The hash in `NOTIFY_STORE` is whatever was current on the development machine when the script was last touched, and it will go stale every time Guix updates `libnotify`.

The right way to make this not matter for your machine is the one in step 1: include `libnotify` in your own Guix Home packages so `notify-send` is on `PATH`. The fallback is then never reached and the version drift is harmless.

If you need to update the fallback for a different reason, find the current store path with:

```bash
guix build libnotify
# or, if libnotify is in your profile:
readlink -f "$(command -v notify-send)"
```

and replace the `NOTIFY_STORE` value at the top of `voxtyper.sh`.

## Step 6 — Bind a keyboard shortcut

The shortcut binding is the same idea as on any distribution: point a global keybind at `~/.local/bin/voxtyper`. Concrete examples follow.

### Sway (Wayland) or i3 (X11)

Add to `~/.config/sway/config` (or `~/.config/i3/config`):

```
bindsym $mod+x exec ~/.local/bin/voxtyper
```

Then reload the compositor (`Mod+Shift+c` on default Sway).

### XFCE

Settings -> Keyboard -> Application Shortcuts -> Add. Command: `/home/<you>/.local/bin/voxtyper`. Choose a key combination.

### KDE Plasma

System Settings -> Shortcuts -> Custom Shortcuts -> Edit -> New -> Global Shortcut -> Command/URL. Command: `/home/<you>/.local/bin/voxtyper`.

### GNOME

Settings -> Keyboard -> View and Customize Shortcuts -> Custom Shortcuts -> Add. Command: `/home/<you>/.local/bin/voxtyper`.

Because `voxtyper.sh` sets its own `PATH`, the keybind does not need to come from a login shell. This is the reason the script is safe to invoke from a `.desktop` file or a window-manager `exec` line.

## Step 7 — Verification checklist

Run these one at a time before relying on the shortcut:

```bash
# Audio path
arecord -f cd -c 1 -t wav /tmp/test.wav -d 3
aplay /tmp/test.wav

# Whisper path
whisper-cli -m ~/.local/share/whisper/ggml-base.bin -f /tmp/test.wav -otxt -of /tmp/test
cat /tmp/test.txt

# Clipboard (X11)
echo "clipboard test" | xclip -selection clipboard
xclip -selection clipboard -o

# Typing (X11) — focus a text field first
xdotool type 'hello from xdotool'

# Notifications
notify-send "VoxTyper" "notification test"
```

If all five steps work, the keybind will too.

## Wayland on Guix

VoxTyper on Guix is documented and tested against X11 sessions. The script supports Wayland (`wl-copy`, `ydotool`), but `ydotool` on Guix requires `ydotoold` to be running and your user to have access to `/dev/uinput`. Getting that wired up declaratively in `home.scm` or the system config is more work than the X11 path, and the failure modes are subtle (the script will appear to succeed but nothing types into the focused field).

If you want to try the Wayland route anyway, swap `xclip`/`xdotool` for `wl-clipboard`/`ydotool` in `home.scm`, run `ydotoold` (as a system service or via a user-level service), and add your user to a group with `/dev/uinput` write access. The clipboard half (`wl-copy`) will work even without `ydotoold`; you just have to paste manually with `Ctrl+V`.

## Troubleshooting

- **`whisper-cli: No such file or directory` or loader errors.** Built outside `guix shell`. Remove `build/`, re-enter the shell, rebuild.
- **`arecord` produces a zero-byte WAV.** `alsa-plugins:pulseaudio` is not installed, so ALSA cannot route to the actual audio server. Add it to `home.scm` and reconfigure.
- **Notifications missing but transcription happens.** `notify-send` is not on `PATH` and the hard-coded fallback path is stale. Add `libnotify` to `home.scm` and reconfigure.
- **Keybind does nothing but `voxtyper` works in a terminal.** The desktop environment is not honouring the binding, or it is bound to a different command. Run `voxtyper` from a terminal first to rule out the script; if that works, the issue is in the DE's shortcut config.
- **TLS errors when downloading the model.** Switch from `wget` to `curl --cacert /etc/ssl/certs/ca-certificates.crt ...`.
- **Recording starts but the second press does nothing.** The script detects a running `arecord` to decide whether to start or stop. Check `pgrep -x arecord`. If there are multiple instances (perhaps from a previous run that crashed), `pkill arecord` and try again.
