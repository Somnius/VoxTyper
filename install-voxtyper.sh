#!/usr/bin/env bash
#
# VoxTyper: install dependencies per distribution.
# Run from the project root (where voxtyper.sh lives).
# Usage: ./install-voxtyper.sh [--no-script] [--dry-run]
#
# Package names differ by distro:
#   - Whisper: Fedora/Nobara = whisper-cpp; Debian/Ubuntu = whisper.cpp; Arch = whisper.cpp (AUR);
#              Gentoo (GURU) = app-accessibility/whisper-cpp; NixOS = openai-whisper-cpp (nixpkgs)
#   - notify-send: Debian/Ubuntu = libnotify-bin; Fedora/Arch/openSUSE/Void/Gentoo/Alpine = libnotify
#   - wl-clipboard, alsa-utils, ydotool (or dotool on Alpine) are usually the same name on supported distros
#

set -e

DRY_RUN=
INSTALL_SCRIPT=1
SCRIPT_NAME="voxtyper.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-script) INSTALL_SCRIPT=0 ;;
    --dry-run)   DRY_RUN=1 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# -----------------------------------------------------------------------------
# Detect distribution from /etc/os-release
# -----------------------------------------------------------------------------
if [[ ! -f /etc/os-release ]]; then
  echo "Cannot detect distribution: /etc/os-release not found." >&2
  exit 1
fi

# shellcheck source=/dev/null
. /etc/os-release

# Normalize: ID_LIKE can be "fedora" or "debian ubuntu" etc.
ID="${ID:-unknown}"
ID_LIKE="${ID_LIKE:-}"

# Prefer ID_LIKE for family (e.g. Nobara has ID=nobara, ID_LIKE=fedora)
if [[ "$ID" == "nobara" ]] \
   || [[ "$ID" == "rocky" ]] || [[ "$ID" == "almalinux" ]] || [[ "$ID" == "centos" ]] || [[ "$ID" == "rhel" ]] \
   || [[ "$ID_LIKE" == *"fedora"* ]] || [[ "$ID_LIKE" == *"rhel"* ]]; then
  FAMILY="fedora"
elif [[ "$ID" == "debian" ]] || [[ "$ID" == "ubuntu" ]] \
      || [[ "$ID" == "pika" ]] || [[ "$ID" == "linuxmint" ]] || [[ "$ID" == "pop" ]] || [[ "$ID" == "zorin" ]] \
      || [[ "$ID" == "neon" ]] || [[ "$ID" == "elementary" ]] || [[ "$ID" == "kali" ]] || [[ "$ID" == "mx" ]] \
      || [[ "$ID_LIKE" == *"debian"* ]] || [[ "$ID_LIKE" == *"ubuntu"* ]]; then
  FAMILY="debian"
elif [[ "$ID" == "arch" ]] \
      || [[ "$ID" == "cachyos" ]] || [[ "$ID" == "endeavouros" ]] || [[ "$ID" == "manjaro" ]] \
      || [[ "$ID" == "garuda" ]] || [[ "$ID" == "arcolinux" ]] \
      || [[ "$ID_LIKE" == *"arch"* ]]; then
  FAMILY="arch"
elif [[ "$ID" == "opensuse-tumbleweed" ]] || [[ "$ID" == "opensuse-leap" ]] || [[ "$ID" == "opensuse-microos" ]] \
      || [[ "$ID_LIKE" == *"suse"* ]]; then
  FAMILY="suse"
elif [[ "$ID" == "void" ]] || [[ "$ID_LIKE" == *"void"* ]]; then
  FAMILY="void"
elif [[ "$ID" == "alpine" ]] || [[ "$ID_LIKE" == *"alpine"* ]]; then
  FAMILY="alpine"
elif [[ "$ID" == "gentoo" ]] || [[ "$ID_LIKE" == *"gentoo"* ]]; then
  FAMILY="gentoo"
elif [[ "$ID" == "nixos" ]] || [[ "$ID_LIKE" == *"nixos"* ]]; then
  FAMILY="nixos"
else
  FAMILY="$ID"
fi

echo "Detected: ID=$ID, FAMILY=$FAMILY"

# -----------------------------------------------------------------------------
# Define packages and install command per family
# -----------------------------------------------------------------------------
run_install() {
  if [[ -n "$DRY_RUN" ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

install_fedora() {
  # Fedora, Nobara, RHEL, Rocky, Alma: whisper-cpp, libnotify (not libnotify-bin)
  local pkgs=(whisper-cpp wl-clipboard alsa-utils libnotify ydotool)
  run_install sudo dnf install -y "${pkgs[@]}"
}

install_debian() {
  # Debian, Ubuntu: whisper.cpp, libnotify-bin for notify-send
  local pkgs=(whisper.cpp wl-clipboard alsa-utils libnotify-bin ydotool)
  if command -v apt-get >/dev/null 2>&1; then
    run_install sudo apt-get update
    run_install sudo apt-get install -y "${pkgs[@]}"
  else
    run_install sudo apt update
    run_install sudo apt install -y "${pkgs[@]}"
  fi
}

install_arch() {
  # Arch: official repos have wl-clipboard, alsa-utils, libnotify, ydotool
  # whisper.cpp is in AUR only
  local main_pkgs=(wl-clipboard alsa-utils libnotify ydotool)
  run_install sudo pacman -Sy --noconfirm --needed "${main_pkgs[@]}"

  if pacman -Q whisper.cpp 2>/dev/null || pacman -Q whisper-cpp 2>/dev/null; then
    echo "Whisper (whisper.cpp or whisper-cpp) already installed."
  else
    if command -v paru >/dev/null 2>&1; then
      run_install paru -Sy --noconfirm --needed whisper.cpp
    elif command -v yay >/dev/null 2>&1; then
      run_install yay -Sy --noconfirm --needed whisper.cpp
    else
      echo "Install whisper.cpp from AUR (e.g. paru -S whisper.cpp or yay -S whisper.cpp)."
    fi
  fi
}

install_suse() {
  # openSUSE: same package names as Fedora for these
  local pkgs=(wl-clipboard alsa-utils libnotify ydotool)
  run_install sudo zypper install -y "${pkgs[@]}"
  # whisper.cpp / whisper-cpp may not be in default repos
  if zypper search whisper 2>/dev/null | grep -q -i whisper; then
    run_install sudo zypper install -y whisper-cpp 2>/dev/null || run_install sudo zypper install -y whisper.cpp 2>/dev/null || true
  else
    echo "Whisper may not be in openSUSE repos; consider building from source or adding a repo."
  fi
}

install_void() {
  # Void Linux: xbps-install, package names mostly match Fedora/Debian
  local pkgs=(alsa-utils libnotify ydotool)
  run_install sudo xbps-install -Sy "${pkgs[@]}"

  # wl-clipboard may or may not be packaged; try if available
  if command -v xbps-query >/dev/null 2>&1 && xbps-query -Rs wl-clipboard >/dev/null 2>&1; then
    run_install sudo xbps-install -Sy wl-clipboard
  else
    echo "wl-clipboard not found in Void repos (or xbps-query missing); install manually if you need Wayland clipboard support."
  fi

  echo "For Whisper on Void, you may need to build whisper.cpp from source or use a container/toolbox."
}

install_alpine() {
  # Alpine: apk, wl-clipboard and libnotify available; no native ydotool but dotool exists.
  local pkgs=(wl-clipboard alsa-utils libnotify)
  run_install sudo apk add --no-cache "${pkgs[@]}"

  # dotool is a rough alternative to ydotool on Alpine
  if apk info dotool >/dev/null 2>&1; then
    run_install sudo apk add --no-cache dotool || true
    echo "On Alpine, ydotool is not packaged; installed dotool instead. Adjust your script if you want to use it."
  else
    echo "On Alpine, ydotool is not packaged; consider installing dotool or building ydotool from source."
  fi

  echo "Whisper.cpp is not in Alpine's main repos as of now; build from source or use a container if needed."
}

install_gentoo() {
  # Gentoo: emerge; categories required for some packages.
  local pkgs=(gui-apps/wl-clipboard media-sound/alsa-utils x11-libs/libnotify x11-misc/ydotool)
  run_install sudo emerge --ask=n --verbose "${pkgs[@]}"

  echo "For Whisper on Gentoo, you can use app-accessibility/whisper-cpp from the GURU overlay (not installed automatically here)."
}

install_nixos() {
  echo "Detected NixOS. System packages are normally managed declaratively."
  echo ""
  echo "Add something like this to your configuration.nix:"
  cat <<'EOF'
  environment.systemPackages = with pkgs; [
    openai-whisper-cpp
    wl-clipboard
    alsa-utils
    libnotify
    ydotool
  ];
EOF
  echo ""
  echo "Then rebuild: sudo nixos-rebuild switch"
}

# -----------------------------------------------------------------------------
# Dispatch and optional script install
# -----------------------------------------------------------------------------
case "$FAMILY" in
  fedora)  install_fedora ;;
  debian)  install_debian ;;
  arch)    install_arch ;;
  suse)    install_suse ;;
  void)    install_void ;;
  alpine)  install_alpine ;;
  gentoo)  install_gentoo ;;
  nixos)   install_nixos ;;
  *)
    # Fallback: try to infer from available package manager
    if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
      install_fedora
    elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
      install_debian
    elif command -v pacman >/dev/null 2>&1; then
      install_arch
    elif command -v zypper >/dev/null 2>&1; then
      install_suse
    else
      echo "Unsupported distribution: $FAMILY (ID=$ID)."
      echo "Install manually: whisper (whisper-cpp or whisper.cpp), wl-clipboard, alsa-utils, libnotify/libnotify-bin, ydotool."
      exit 1
    fi
    ;;
esac

if [[ "$INSTALL_SCRIPT" -eq 1 ]]; then
  INSTALLER_DIR="$(dirname "$(realpath "$0" 2>/dev/null || echo "$0")")"
  SCRIPT_SRC="${SCRIPT_SRC:-$INSTALLER_DIR/$SCRIPT_NAME}"
  if [[ ! -f "$SCRIPT_SRC" ]]; then
    SCRIPT_SRC="$(pwd)/$SCRIPT_NAME"
  fi
  if [[ -f "$SCRIPT_SRC" ]]; then
    DEST="$HOME/.local/bin/voxtyper"
    mkdir -p "$HOME/.local/bin"
    if [[ -n "$DRY_RUN" ]]; then
      echo "[dry-run] cp $SCRIPT_SRC $DEST && chmod +x $DEST"
    else
      cp "$SCRIPT_SRC" "$DEST"
      chmod +x "$DEST"
      echo "Installed script to $DEST"
    fi
  else
    echo "Script not found: $SCRIPT_SRC (run from project root or set SCRIPT_SRC)."
  fi
fi

echo ""
echo "Next steps:"
echo "  1. Download the Whisper model: mkdir -p ~/.local/share/whisper && cd ~/.local/share/whisper && wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
echo "  2. Enable ydotoold: sudo systemctl enable --now ydotoold.service"
echo "  3. Bind ~/.local/bin/voxtyper to a shortcut (e.g. Meta+X) in your desktop environment."
