# VoxTyper on Guix System and NixOS

Guix and NixOS do not behave like a Fedora or an Arch. There is no global package install command you can usefully run, the filesystem layout is unusual, and binaries from "outside" the distro often refuse to run because they expect a `/usr` that does not exist. Getting `voxtyper.sh` to behave the same way it does on a traditional distro took a few small accommodations. This document records what those are and why they are there, so anyone repeating the setup does not have to rediscover them.

The cross-distro README and the Nobara walkthrough cover the normal case. This file is the addendum for the immutable / declarative side.

## What is different on these systems

- **No imperative installs.** `sudo dnf install ...` does not have an equivalent. Packages have to be declared in a configuration file (`configuration.nix` on NixOS, `home.scm` or the system config on Guix) and then materialised by a rebuild.
- **Binaries live under hashed store paths.** On NixOS that is `/nix/store`, on Guix that is `/gnu/store`. Everything userspace resolves through symlinks that point into one of those stores.
- **No standard `/usr/bin`.** A script that was written assuming `notify-send` will be on `PATH` because some `.desktop` launcher or display manager set it up that way will fail silently when invoked from a window-manager keybind.
- **The system glibc is the only glibc.** A `whisper-cli` built on a Fedora host will not run on Guix or NixOS, because its dynamic loader path does not exist. It has to be built on the target system.

`voxtyper.sh` is written so that the same script works on a stock Fedora, on Guix, and on NixOS without modification. The next two sections describe the changes that made that possible.

## Accommodations in the script itself

If you read the top of `voxtyper.sh` you will see two things that look out of place for a plain Linux script:

```bash
export PATH="$HOME/.local/bin:$HOME/.guix-home/profile/bin:/run/current-system/profile/bin:/usr/sbin:/usr/bin:$PATH"
```

The script sets its own `PATH` instead of trusting whatever the desktop environment passed in. The two unusual entries are:

- `$HOME/.guix-home/profile/bin` Guix Home installs user-level packages into a profile rooted at `~/.guix-home`. Binaries land in `profile/bin`. Without this entry, a `voxtyper` invoked from a KDE Custom Shortcut on a Guix system would not see `xclip`, `xdotool`, or `arecord`.
- `/run/current-system/profile/bin` System-level packages on Guix (and the analogous location on NixOS variants) live under this profile. Adding it makes the script work even if the user has installed the helper tools system-wide instead of per user.

The second accommodation is the `notify-send` fallback:

```bash
NOTIFY_STORE="/gnu/store/zz1a4i2x6ahgyvs13pl2q5qg979f67ng-libnotify-0.8.8/bin/notify-send"
if command -v notify-send >/dev/null 2>&1; then
  NOTIFY_SEND="notify-send"
elif [[ -x "$NOTIFY_STORE" ]]; then
  NOTIFY_SEND="$NOTIFY_STORE"
fi
```

On a Guix host the `notify-send` binary may not be in any profile that the script can see (libnotify is provided by `%desktop-services` and ends up tucked under a store path that no user-facing `PATH` includes by default). The fallback hits the exact store path on the development host. If neither is found, the script prints to stdout instead of notifying, so the rest of the pipeline still works.

That hard-coded path is fragile across libnotify versions: when Guix updates libnotify the hash changes. If the fallback ever stops resolving, the fix is either to add `libnotify` to your Guix profile (so `notify-send` ends up on `PATH` properly) or to update the path to the new store hash.

## Guix System

### Helper packages

The installer (`install-voxtyper.sh`) deliberately does not try to install anything on Guix, because doing it imperatively is the wrong shape for the system. Declare the tools in `~/.config/guix/home.scm`:

```
(home-environment
 (packages
  (specifications->packages
   (list "alsa-utils"
         "alsa-plugins:pulseaudio"   ; lets arecord talk to PulseAudio/PipeWire
         "xclip"
         "xdotool"))))
```

Then apply the change:

```bash
guix home reconfigure ~/.config/guix/home.scm
```

`libnotify` is normally pulled in by `%desktop-services` at the system level, which is why it is not in the user profile. If `notify-send` is missing after reconfiguring (run `command -v notify-send`), add `libnotify` to the same list and reconfigure again.

Wayland note: VoxTyper on Guix targets X11. If you are on a Wayland session, swap `xclip` and `xdotool` for `wl-clipboard` and `ydotool`, and arrange for `ydotoold` to be running (this is non-trivial on Guix; running on X11 is the path of least resistance).

### Building whisper.cpp on Guix

Building outside a Guix environment will produce a binary that the dynamic loader cannot start. Use `guix shell` so the build picks up Guix's GCC and glibc:

```bash
mkdir -p ~/dev && cd ~/dev
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

guix shell gcc-toolchain cmake make -- bash -c "
  rm -rf build && \
  cmake -B build -DCMAKE_BUILD_TYPE=Release && \
  cmake --build build -j\$(nproc) && \
  cp build/bin/whisper-cli ~/.local/bin/whisper-cli
"
```

The `rm -rf build` matters: if you previously built outside `guix shell`, CMake will have cached compiler paths that no longer make sense inside the shell.

### Downloading the model on Guix

`wget` on Guix is sometimes configured in a way that cannot find a usable certificate bundle, which produces a confusing TLS error against `huggingface.co`. `curl` with the system CA bundle works:

```bash
mkdir -p ~/.local/share/whisper
curl --cacert /etc/ssl/certs/ca-certificates.crt \
  -L -o ~/.local/share/whisper/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

### Wiring it to a shortcut

Same idea as any other distro: bind `~/.local/bin/voxtyper` to a key combination in your desktop environment or compositor. Because the script sets its own `PATH`, the keybinding does not need to come from a login shell, and the X session does not need to inherit the Guix profile to find the tools.

## NixOS

### Helper packages

Declare the helper tools in `configuration.nix`:

```nix
environment.systemPackages = with pkgs; [
  wl-clipboard   # or xclip if you are on X11
  alsa-utils
  libnotify
  ydotool        # or xdotool on X11
];

# If you want ydotool to type into the focused window:
programs.ydotool.enable = true;
```

Apply with:

```bash
sudo nixos-rebuild switch
```

`programs.ydotool.enable = true` sets up the daemon and the `/dev/uinput` permissions in one go. Without it you would still get clipboard copy, but typing would silently no-op.

The installer prints a similar snippet if you run `./install-voxtyper.sh` on a NixOS host. It does not run `nixos-rebuild` for you because editing system config and rebuilding is the user's decision, not the installer's.

### Building whisper.cpp on NixOS

The cleanest path is `nix-shell` (or `nix shell` with flakes) so the build uses the Nix toolchain:

```bash
cd ~/dev
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

nix-shell -p gcc cmake gnumake --run '
  rm -rf build && \
  cmake -B build -DCMAKE_BUILD_TYPE=Release && \
  cmake --build build -j"$(nproc)" && \
  cp build/bin/whisper-cli ~/.local/bin/whisper-cli
'
```

If you prefer flakes:

```bash
nix shell nixpkgs#gcc nixpkgs#cmake nixpkgs#gnumake --command bash -c '
  rm -rf build && \
  cmake -B build -DCMAKE_BUILD_TYPE=Release && \
  cmake --build build -j"$(nproc)" && \
  cp build/bin/whisper-cli ~/.local/bin/whisper-cli
'
```

The resulting `whisper-cli` ends up in `~/.local/bin`, which is where the VoxTyper script looks first.

### Model and keybinding

The model download is the same `wget` line from the main README. NixOS does not have the certificate issue Guix sometimes has, so plain `wget` works.

For the keybinding, GNOME's `Custom Shortcuts` or KDE's `Custom Shortcuts` both work. On Wayland sessions, also confirm `ydotoold` is running (`systemctl --user status ydotoold` or the system unit, depending on how you enabled it).

## Quick verification

The same four checks from the Nobara guide apply unchanged. The interesting one on Guix and NixOS is the first one, which catches PATH or profile mistakes before you get all the way to a keybind that does nothing:

```bash
command -v whisper-cli && command -v arecord && command -v notify-send && \
  (command -v xclip || command -v wl-copy) && \
  (command -v xdotool || command -v ydotool) && \
  echo "all tools resolved"
```

If that prints `all tools resolved` from a regular shell, the keybinding will work too, because `voxtyper.sh` sets the same `PATH` you are already using.

## Known sharp edges

- The hard-coded `/gnu/store/...libnotify.../bin/notify-send` fallback in `voxtyper.sh` is tied to a specific libnotify version. When Guix updates libnotify, that path stops resolving. The right long-term fix is to put `libnotify` in your Guix user profile so `notify-send` is on `PATH` and the fallback is never reached.
- `ydotool` on Guix is workable but requires `ydotoold` to be running and `/dev/uinput` to be writable by your user. If that is a fight you do not want to have, run an X11 session on Guix and use `xdotool` instead. This is also why the default Guix `home.scm` snippet above lists `xclip` and `xdotool` rather than the Wayland pair.
- Building `whisper.cpp` outside a `guix shell` or `nix-shell` will silently succeed and produce a binary that exits with a cryptic loader error at runtime. If `whisper-cli --help` fails with something about a missing interpreter, rebuild inside the shell.
