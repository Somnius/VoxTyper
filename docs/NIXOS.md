# VoxTyper on NixOS

This is the full walkthrough for getting VoxTyper running on NixOS. It assumes a working NixOS installation with a graphical session. Both system-level configuration (`configuration.nix`) and per-user configuration (Home Manager) work; this document covers both, with the system-level path as the default because it is the lowest-friction approach.

NixOS is declarative the same way Guix is: packages are described in a configuration file and materialised by a rebuild. The same accommodations `voxtyper.sh` makes for Guix (setting its own `PATH` rather than trusting an inherited environment) also make it work cleanly here.

## Why NixOS needs its own walkthrough

NixOS differs from a typical distribution in three relevant ways:

- **No imperative installs at the system level.** `sudo nix-env -i` exists but is the wrong tool for VoxTyper. The helper packages and the `ydotoold` daemon belong in `configuration.nix` so they survive rebuilds and roll back cleanly.
- **Binaries live under `/nix/store/<hash>-<name>-<version>/`.** Profile symlinks (`/run/current-system/sw/bin`, `~/.nix-profile/bin`) point into the store. Anything that hard-codes `/usr/bin` will not work.
- **Binaries built outside Nix usually do not run.** A `whisper-cli` copied in from another distribution will fail with a missing dynamic loader. `whisper.cpp` has to be built inside a `nix-shell` so it links against the Nix-provided glibc.

`voxtyper.sh` accommodates the first two by managing its own `PATH`. The third is handled by always building `whisper.cpp` inside `nix-shell` or `nix shell` (see step 3).

## What you will end up with

- Helper tools (`wl-clipboard` or `xclip`, `ydotool` or `xdotool`, `arecord`, `notify-send`) declared in `configuration.nix` (or `home.nix`) and materialised by `nixos-rebuild`.
- `programs.ydotool.enable = true` (on Wayland) so the `ydotoold` daemon and `/dev/uinput` permissions are set up declaratively.
- `whisper-cli` built from source against the Nix toolchain, installed at `~/.local/bin/whisper-cli`.
- `ggml-base.bin` model under `~/.local/share/whisper/`.
- `voxtyper.sh` installed as `~/.local/bin/voxtyper`, bound to a key combination by your desktop environment.

## Step 1 — Declare the helper packages

Open `/etc/nixos/configuration.nix` and add the helpers to `environment.systemPackages`. The exact list depends on whether you are on Wayland or X11.

### Wayland (KDE Plasma 6, GNOME on Wayland, sway, niri, Hyprland, etc.)

```nix
{ config, pkgs, ... }:
{
  # ... your existing configuration ...

  environment.systemPackages = with pkgs; [
    wl-clipboard   # provides wl-copy / wl-paste
    alsa-utils     # provides arecord
    libnotify      # provides notify-send
    ydotool        # provides ydotool (the typing tool)
  ];

  # Daemon and uinput permissions for ydotool, in one go:
  programs.ydotool.enable = true;
}
```

### X11 (i3, XFCE, Plasma X11 session, etc.)

```nix
{ config, pkgs, ... }:
{
  # ... your existing configuration ...

  environment.systemPackages = with pkgs; [
    xclip          # provides xclip
    xdotool        # provides xdotool
    alsa-utils     # provides arecord
    libnotify      # provides notify-send
  ];
}
```

Apply the configuration:

```bash
sudo nixos-rebuild switch
```

If the rebuild fails, fix the syntax error it reports and rerun. A successful `nixos-rebuild switch` automatically activates the new profile; you do not need to reboot.

Verify the tools resolved:

```bash
# Wayland:
command -v arecord notify-send wl-copy ydotool

# X11:
command -v arecord notify-send xclip xdotool
```

All four should print paths under `/run/current-system/sw/bin/`. If any are missing, double-check you added them to `environment.systemPackages` and that the rebuild succeeded.

The line at the top of `voxtyper.sh` that puts the system profile on the search path:

```bash
export PATH="$HOME/.local/bin:$HOME/.guix-home/profile/bin:/run/current-system/profile/bin:/usr/sbin:/usr/bin:$PATH"
```

The `/run/current-system/profile/bin` entry covers Guix; on NixOS the equivalent location (`/run/current-system/sw/bin`) is already on `PATH` in any graphical session, so the script picks up the system packages without modification.

## Step 2 — Optional: per-user packages with Home Manager

If you prefer per-user installation (so each user controls their own VoxTyper helpers) and you already use Home Manager, the same packages can go into `~/.config/home-manager/home.nix` (or wherever your Home Manager config lives):

```nix
{ pkgs, ... }:
{
  # ... your existing Home Manager config ...

  home.packages = with pkgs; [
    wl-clipboard
    alsa-utils
    libnotify
    ydotool
  ];

  # If your Home Manager setup supports it, you can also enable services here.
}
```

Apply:

```bash
home-manager switch
```

Note that `programs.ydotool.enable` lives at the *system* level (it sets up the daemon and `/dev/uinput` permissions). You still need that in `configuration.nix` even if you put the binaries in Home Manager. The reason is that Home Manager runs as your user and cannot grant kernel-level access to `/dev/uinput`.

## Step 3 — Build whisper.cpp inside `nix-shell`

The single critical thing is that `whisper.cpp` must be built inside a `nix-shell` (or `nix shell`) so the resulting binary links against the Nix toolchain. Building it on another distro and copying the binary in will not work.

### Without flakes (`nix-shell`)

```bash
mkdir -p ~/dev
cd ~/dev
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

nix-shell -p gcc cmake gnumake --run '
  rm -rf build && \
  cmake -B build -DCMAKE_BUILD_TYPE=Release && \
  cmake --build build -j"$(nproc)" && \
  mkdir -p ~/.local/bin && \
  cp build/bin/whisper-cli ~/.local/bin/whisper-cli
'
```

### With flakes (`nix shell`)

If you have `experimental-features = nix-command flakes` set:

```bash
mkdir -p ~/dev
cd ~/dev
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

nix shell nixpkgs#gcc nixpkgs#cmake nixpkgs#gnumake --command bash -c '
  rm -rf build && \
  cmake -B build -DCMAKE_BUILD_TYPE=Release && \
  cmake --build build -j"$(nproc)" && \
  mkdir -p ~/.local/bin && \
  cp build/bin/whisper-cli ~/.local/bin/whisper-cli
'
```

Notes on both commands:

- `rm -rf build` is intentional. CMake caches compiler paths in `build/CMakeCache.txt`; if you previously built outside the shell, those cached paths will point at non-existent locations and the rebuild will fail or pick the wrong toolchain.
- `gcc` here is the Nix-provided GCC, which carries its own libc headers and linker. That is what makes the resulting binary work.
- `~/.local/bin/whisper-cli` is the path `voxtyper.sh` looks for first. It lives outside the Nix store, so it survives `nixos-rebuild` and rollbacks.

Verify the binary works from outside the shell:

```bash
whisper-cli --help | head -3
```

If you get `bash: /home/.../whisper-cli: No such file or directory` (with the file clearly present), the dynamic loader is missing. That means the build leaked the host toolchain. Remove `build/`, re-enter the Nix shell, and rebuild.

## Step 4 — Download the Whisper model

The default model is the multilingual base:

```bash
mkdir -p ~/.local/share/whisper
cd ~/.local/share/whisper
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

NixOS has the system CA bundle in the right places by default, so `wget` works without the `--cacert` workaround that Guix sometimes needs.

For better accuracy at the cost of latency, swap to `ggml-small.bin`, `ggml-medium.bin`, or `ggml-large.bin`. Download the new file into the same directory and update the `MODEL=` line near the top of `voxtyper.sh`.

## Step 5 — Install the VoxTyper script

The installer (`install-voxtyper.sh`) detects NixOS and prints a configuration snippet instead of trying to install packages, which is the right behavior. To install the script itself, run the installer with `--no-script` skipped, or copy the script in by hand:

```bash
mkdir -p ~/.local/bin
cp ./voxtyper.sh ~/.local/bin/voxtyper
chmod +x ~/.local/bin/voxtyper
```

Run it once from a terminal to confirm everything resolves:

```bash
voxtyper
# should show a "Now listening for VoxTyper" notification
voxtyper
# stops, transcribes, exits cleanly
```

If the notifications appear in the terminal as `VoxTyper: ...` instead of as desktop notifications, `notify-send` is not on `PATH`. Re-check that `libnotify` is in `environment.systemPackages` and that you rebuilt afterwards.

## Step 6 — Configure ydotool (Wayland only)

`programs.ydotool.enable = true` in `configuration.nix` does most of the work: it starts `ydotoold` as a system service and grants the necessary `/dev/uinput` permissions to the standard `input` group.

Verify the daemon is running:

```bash
systemctl status ydotoold
```

If it is not running, check the service unit (`systemctl cat ydotoold`) and the journal (`journalctl -u ydotoold`).

You may also need to add your user to the `input` group; on most setups `programs.ydotool.enable` handles this, but you can confirm with:

```bash
groups
```

If `input` is not listed, add yourself in `configuration.nix`:

```nix
users.users.<your-username>.extraGroups = [ "input" ];
```

Then `sudo nixos-rebuild switch` and log out and back in for the group change to take effect.

On X11, this step is unnecessary. `xdotool` does not need a daemon or special permissions.

## Step 7 — Bind a keyboard shortcut

Point a global keybind at `~/.local/bin/voxtyper`. A few common environments:

### GNOME

Settings -> Keyboard -> View and Customize Shortcuts -> Custom Shortcuts -> Add. Command: `/home/<you>/.local/bin/voxtyper`.

### KDE Plasma

System Settings -> Shortcuts -> Custom Shortcuts -> Edit -> New -> Global Shortcut -> Command/URL. Command: `/home/<you>/.local/bin/voxtyper`.

### Sway

Add to `~/.config/sway/config`:

```
bindsym $mod+x exec ~/.local/bin/voxtyper
```

### Hyprland

Add to `~/.config/hypr/hyprland.conf`:

```
bind = SUPER, X, exec, ~/.local/bin/voxtyper
```

### XFCE

Settings -> Keyboard -> Application Shortcuts -> Add. Command: `/home/<you>/.local/bin/voxtyper`.

Because `voxtyper.sh` sets its own `PATH`, the keybind does not need to come from a login shell. This is what makes it safe to invoke directly from a window-manager `bind` line or a `.desktop` file.

## Step 8 — Verification checklist

Run these one at a time before relying on the shortcut:

```bash
# Audio path
arecord -f cd -c 1 -t wav /tmp/test.wav -d 3
aplay /tmp/test.wav

# Whisper path
whisper-cli -m ~/.local/share/whisper/ggml-base.bin -f /tmp/test.wav -otxt -of /tmp/test
cat /tmp/test.txt

# Clipboard (Wayland)
echo "clipboard test" | wl-copy
wl-paste

# Clipboard (X11)
echo "clipboard test" | xclip -selection clipboard
xclip -selection clipboard -o

# Typing (Wayland) — focus a text field first
ydotool type 'hello from ydotool'

# Typing (X11) — focus a text field first
xdotool type 'hello from xdotool'

# Notifications
notify-send "VoxTyper" "notification test"
```

If all relevant steps work, the keybind will too.

## Troubleshooting

- **`whisper-cli: No such file or directory` or loader errors.** Built outside `nix-shell`. Remove `build/`, re-enter the shell, rebuild.
- **`ydotool` does nothing.** Either `ydotoold` is not running (`systemctl status ydotoold`), or your user is not in the `input` group. Confirm `programs.ydotool.enable = true` in `configuration.nix` and rebuild. Log out and back in after a group change.
- **Notifications missing but transcription happens.** `notify-send` is not on `PATH`. Confirm `libnotify` is in `environment.systemPackages` and rebuild.
- **Recording starts but the second press does nothing.** The script uses `pgrep -x arecord` to decide between starting and stopping. Check for orphaned `arecord` processes from a previous run; `pkill arecord` and try again.
- **Keybind does nothing, but `voxtyper` from a terminal works.** The desktop environment is not honouring the binding, or the path in the shortcut is wrong. Use the absolute path (`/home/<you>/.local/bin/voxtyper`) rather than a relative one or `~/`.
- **The shortcut works from one session type but not the other.** You probably switched between X11 and Wayland sessions and the helper tools you installed only cover one of them. Check `loginctl show-session $XDG_SESSION_ID -p Type` and adjust `environment.systemPackages` accordingly.
- **`nix-shell` is slow on every build.** First-time use builds or substitutes the entire toolchain. Subsequent invocations reuse the store and are fast.

## Rolling back

NixOS rebuilds are checkpointed automatically. If something goes wrong after a `nixos-rebuild switch`, you can roll back to the previous generation from the boot menu, or with:

```bash
sudo nixos-rebuild switch --rollback
```

Nothing about VoxTyper escapes that mechanism, because everything you declared is in `configuration.nix`. The bits that live outside it (`~/.local/bin/whisper-cli`, the model file, `voxtyper.sh`) are not managed by Nix, so they survive rebuilds and rollbacks but are also your responsibility to back up.
