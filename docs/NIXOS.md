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

## Going fully declarative (NixOS-specific)

> **Scope.** Everything below this heading is NixOS-only. It uses `pkgs.writeShellScriptBin`, `pkgs.fetchurl`, `lib.makeBinPath`, Home Manager, and plasma-manager — none of which exist on Guix or on a non-Nix distribution. If you are reading this on Guix, see [`GUIX.md`](GUIX.md) for the equivalent `home.scm` patterns; if you are on a non-Nix system, stop at the end of "Step 8 — Verification checklist" above.

Everything above is the imperative path: install helpers through `configuration.nix`, but keep the Whisper binary, the model file, and the VoxTyper script in `~/.local/bin` and `~/.local/share`. That works, but it leaves three moving pieces (`whisper-cli`, `ggml-base.bin`, `voxtyper`) outside Nix, where they can drift, get lost, or stop working after a system upgrade without any signal from `nixos-rebuild`.

The fully declarative alternative pulls all three into the Nix store: the Whisper binary becomes the nixpkgs `whisper-cpp` derivation, the model becomes a `fetchurl` with a pinned SHA, and the VoxTyper script becomes a `writeShellScriptBin` package whose `PATH` is constructed from `lib.makeBinPath`. The result is a Home Manager profile that produces an identical `voxtyper` invocation on every rebuild, with byte-for-byte reproducible dependencies. This section walks through that approach end to end. It is what the maintainer of this project is actually running on a daily-driver NixOS / KDE Plasma 6 / Wayland machine. None of the Nix idioms below have a Guix or plain-Linux equivalent that "just works" the same way — the techniques are NixOS-flavoured by design.

### Why bother

Doing it this way buys four concrete things that the imperative path does not:

- **Reproducibility.** Every dependency the script calls — including the Whisper binary and the libnotify version that provides `notify-send` — is pinned by the same flake lock that pins the rest of your system. There is no version drift between the `whisper-cli` that worked yesterday and the one that runs today.
- **Atomic upgrades and rollbacks.** A bad `nixos-rebuild switch` is a single `--rollback` away from being reverted. Imperative `~/.local/bin/whisper-cli` builds are not.
- **The script's `PATH` becomes irrelevant to anything in your shell.** `lib.makeBinPath` bakes the exact store paths of `whisper-cpp`, `wl-clipboard`, `wtype`, `libnotify`, `pipewire`, `pulseaudio`, `alsa-utils`, and `util-linux` into the script. The keybind never needs a login shell, the desktop environment never needs the right `PATH`, and there is no `/gnu/store` fallback to keep up to date.
- **The keybind is in source control.** Through plasma-manager (KDE) or the equivalent for your DE, the shortcut that triggers `voxtyper` is declared alongside the package itself.

### Package the script (NixOS)

Create a file `packages/voxtyper.nix` next to your flake (or wherever you keep custom packages). `pkgs.writeShellScriptBin` is a nixpkgs builder; it does not exist on other systems. The structure is `writeShellScriptBin` wrapped around the script body, with `lib.makeBinPath` producing the prefix for `PATH`:

```nix
{ pkgs, lib }:

pkgs.writeShellScriptBin "voxtyper" ''
  # VoxTyper — offline push-to-talk dictation for Wayland (KDE Plasma 6)
  export PATH="${lib.makeBinPath (with pkgs; [
    whisper-cpp
    wl-clipboard
    wtype
    libnotify
    pipewire
    pulseaudio
    alsa-utils
    util-linux
  ])}:$HOME/.local/bin:$PATH"

  MODEL="''${HOME}/.local/share/whisper/ggml-base.bin"
  WHISPER_BIN="''${WHISPER_BIN:-whisper-cli}"

  # ... script body, with all Nix string interpolations escaped as ''${...}
  # so Nix does not try to substitute them at build time.
''
```

A few non-obvious bits in the template above:

- The script string is a Nix double-quoted multi-line string. Anything that looks like `${...}` would be evaluated by Nix unless escaped as `''${...}`. Every shell variable expansion inside the script body has to use the double-quote escape form.
- `lib.makeBinPath [pkg1 pkg2 ...]` produces `${pkg1}/bin:${pkg2}/bin:...`, where each `${pkg}` is the store path of the package. The result is concatenated into `PATH` at build time, not runtime. The resulting `voxtyper` binary contains the exact `/nix/store/...-whisper-cpp-1.8.4/bin` path baked in.
- `$HOME/.local/bin` is appended after the store paths so the user can still shadow individual tools for testing, but the default is always the pinned Nix versions.

### Use the nixpkgs `whisper-cpp` package (NixOS)

The README in this repository recommends building `whisper.cpp` from source rather than installing the distro package, because several distros pull in CUDA, ROCm, OpenVINO, or large GIS dependency chains. nixpkgs is the exception: `pkgs.whisper-cpp` is a clean, CPU-only build with no GPU runtime dependencies. Including it in the package list above is the right call on NixOS.

Verify what gets pulled in if you are unsure:

```bash
nix-store -q --references "$(nix-build '<nixpkgs>' -A whisper-cpp --no-out-link)"
```

You should see a short list (bash, glibc, gcc-libs) and nothing GPU-related.

### Package the model (NixOS)

The Whisper model is a 142 MB binary blob. Fetching it imperatively with `wget` works, but the model file then lives outside Nix and has no integrity check. `pkgs.fetchurl` with a pinned `sha256` solves both problems:

```nix
# packages/whisper-model.nix
{ pkgs, lib, ... }:

pkgs.fetchurl {
  url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin";
  sha256 = "1zifp9gk9220vysx8a00mzf2sy05ni4l6crx95baivhlvp1mpvb0";
  name = "whisper-ggml-base.bin";
}
```

To get the `sha256` for a new model, start with `sha256 = lib.fakeHash;` and run a build — Nix will print the actual hash in the error message, which you then paste in.

Place the file under `~/.local/share/whisper/ggml-base.bin` via Home Manager so the script's hardcoded `MODEL` path keeps working:

```nix
home.file.".local/share/whisper/ggml-base.bin".source = whisperModel;
```

The result is a read-only symlink from `~/.local/share/whisper/ggml-base.bin` into the Nix store. Updates to the model are atomic; rollbacks restore the previous version.

### Wire it into Home Manager (NixOS / Home Manager)

In `home.nix` (or wherever your Home Manager configuration lives):

```nix
{ config, pkgs, ... }:
let
  voxtyper     = pkgs.callPackage ../../packages/voxtyper.nix     { };
  whisperModel = pkgs.callPackage ../../packages/whisper-model.nix { };
in
{
  home.packages = with pkgs; [
    voxtyper
    whisper-cpp   # so `whisper-cli` resolves outside the script too
  ];

  home.file.".local/share/whisper/ggml-base.bin".source = whisperModel;
}
```

After `nixos-rebuild switch` (or `home-manager switch` if you manage Home Manager separately), the `voxtyper` binary appears in `/etc/profiles/per-user/<you>/bin/voxtyper`, the model appears under `~/.local/share/whisper/`, and `whisper-cli` is available standalone for testing.

### Wire the keybind through plasma-manager (NixOS / KDE)

`plasma-manager` is a Home Manager module from `nix-community`. Add it to your flake inputs and to your Home Manager `sharedModules` as you would any other plasma-manager configuration. If you use it, the KDE shortcut becomes declarative too:

```nix
# In your plasma-manager config:
programs.plasma.hotkeys.commands.voxtyper = {
  name    = "VoxTyper";
  key     = "Meta+V";
  command = "/etc/profiles/per-user/lef/bin/voxtyper";
};
```

Use the absolute store-profile path, not `~/.local/bin/voxtyper` and not a bare `voxtyper`. The KDE shortcut runner does not necessarily see Home Manager's profile on its `PATH` when it launches commands, so the fully-qualified path is the safe choice.

For non-KDE environments, use whatever your declarative shortcut mechanism is. For Sway, that is a `bindsym` line in the Sway config (which can be generated from Home Manager). For Hyprland, a `bind = ...` line. The principle is the same: keep the keybind in source control next to the package.

### Improvements that the script itself ships with (script-level, not NixOS-specific)

The five improvements below live inside the script body that `writeShellScriptBin` wraps. They are not Nix features, they do not require Home Manager, and they would work copied verbatim into `~/.local/bin/voxtyper` on Fedora, Arch, or anything else. They are documented here because the Nix package is the version that has them today; the portable `voxtyper.sh` at the root of this repository is a more conservative variant.

The `voxtyper.sh` in the root of this repository is the portable, distro-agnostic version. The Nix-packaged variant described above tends to evolve faster because the maintainer's daily-driver uses it. As of this writing, it differs from the repo script in five ways that are worth knowing about:

1. **Audio backend fallback chain.** It tries `parecord --channels=1 --rate=16000` first (PulseAudio at the exact format Whisper actually wants, avoiding a runtime resample), then `pw-record` (PipeWire's native recorder), and only falls back to `arecord -f cd -c 1` if neither is present. On a PipeWire/PulseAudio host, `arecord` is the slowest of the three and the one most likely to produce a zero-byte WAV under unusual permissions.
2. **`wtype` instead of `ydotool` for typing on Wayland.** `wtype` talks the virtual-keyboard Wayland protocol directly, so it does not need a `ydotoold` daemon, does not need `/dev/uinput` permissions, and does not need a group membership change. It works on KDE Plasma 6, Sway, Hyprland, and other wlroots-based compositors without setup. The script tries `wtype`, falls back to `wl-copy` if `wtype` fails (e.g. the focused surface refuses synthetic input), and writes the transcript to `/tmp/voxtyper-last.txt` as a last resort.
3. **PID-file mutex in `XDG_RUNTIME_DIR`.** Two presses landing close together would otherwise interleave. The script writes its own PID to `$XDG_RUNTIME_DIR/voxtyper.lock` on entry and exits early if a previous instance is still alive. `flock(1)` is deliberately not used here: the recorder is backgrounded, and the child inherits the locked fd, which would hold the lock until the recorder exits and break the next invocation.
4. **KDE key-down/key-up debounce.** KDE Plasma sometimes fires a global shortcut on both press and release. The script tracks the start time in `$XDG_RUNTIME_DIR/voxtyper.state` and treats any second press within two seconds of the first as a spurious key-up, ignoring it silently. Without this, every recording would stop a fraction of a second after it started.
5. **Debug log.** Every invocation appends to `$XDG_RUNTIME_DIR/voxtyper-debug.log`, recording the audio backend chosen, the whisper-cli output, the typed length, and any failure. When something stops working, that log is the first place to look.

These are not features that require Nix; the same script body would work copied into `~/.local/bin/voxtyper` on any distribution. They are written up here because the Nix package is where they live today.

### Verification (NixOS)

After the rebuild:

```bash
which voxtyper                # should be under /etc/profiles/per-user/<you>/bin
readlink -f "$(which voxtyper)"  # should resolve into /nix/store/...
readlink -f ~/.local/share/whisper/ggml-base.bin  # should resolve into /nix/store/...

voxtyper                      # first press: notification appears, recording starts
sleep 3
voxtyper                      # second press: stops, transcribes, types or copies
```

The two `readlink -f` checks are the giveaway that the declarative path took. If either resolves to something outside `/nix/store`, an imperative install is still shadowing the Nix-managed one. Remove the imperative copy from `~/.local/bin` (and the symlink under `~/.local/share/whisper/` if it points outside the store) and re-test.

If the second press fails to type into the active window but the clipboard does end up with the right text, the issue is the focused surface, not the script. Some applications (e.g. password fields, some Electron apps under Wayland) refuse synthetic input.
