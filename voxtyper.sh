#!/usr/bin/env bash

# VoxTyper 0.4.0 — offline push-to-talk dictation (X11/Wayland)
# Uses whisper.cpp (whisper-cli), xclip/wl-copy, arecord, libnotify, and xdotool/ydotool.

# --- Config ---
export PATH="$HOME/.local/bin:$HOME/.guix-home/profile/bin:/run/current-system/profile/bin:/usr/sbin:/usr/bin:$PATH"

MODEL="${HOME}/.local/share/whisper/ggml-base.bin"

WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"

TMP_WAV="/tmp/whisper-record.wav"
TMP_PREFIX="/tmp/whisper-output"
OUTPUT_FILE="${TMP_PREFIX}.txt"

NOTIFY_SEND=""
NOTIFY_STORE="/gnu/store/zz1a4i2x6ahgyvs13pl2q5qg979f67ng-libnotify-0.8.8/bin/notify-send"
if command -v notify-send >/dev/null 2>&1; then
  NOTIFY_SEND="notify-send"
elif [[ -x "$NOTIFY_STORE" ]]; then
  NOTIFY_SEND="$NOTIFY_STORE"
fi

notify() {
  if [[ -n "$NOTIFY_SEND" ]]; then
    "$NOTIFY_SEND" "VoxTyper" "$1"
  else
    printf 'VoxTyper: %s\n' "$1"
  fi
}

# --- Second press: stop recording and transcribe ---
if pgrep -x "arecord" >/dev/null 2>&1; then
  pkill -INT arecord
  notify "Stopped VoxTyper — transcribing..."

  if [[ ! -f "$MODEL" ]]; then
    notify "Model not found: $MODEL"
    exit 1
  fi

  if ! command -v "$WHISPER_BIN" >/dev/null 2>&1; then
    notify "Whisper CLI '$WHISPER_BIN' not found (set WHISPER_BIN)"
    exit 1
  fi

  "$WHISPER_BIN" -m "$MODEL" -f "$TMP_WAV" -otxt -of "$TMP_PREFIX" --language auto \
    >/dev/null 2>&1

  if [[ -s "$OUTPUT_FILE" ]]; then
    text="$(tr '\n' ' ' < "$OUTPUT_FILE" | sed 's/[[:space:]]\+/ /g')"

    # Copy to clipboard (prefer X11, fall back to Wayland)
    if command -v xclip >/dev/null 2>&1; then
      printf '%s' "$text" | xclip -selection clipboard
    elif command -v wl-copy >/dev/null 2>&1; then
      printf '%s' "$text" | wl-copy
    fi

    # Type into active window (prefer xdotool on X11, fall back to ydotool on Wayland)
    if command -v xdotool >/dev/null 2>&1; then
      xdotool type "$text"
    elif command -v ydotool >/dev/null 2>&1; then
      ydotool type "$text"
    fi
  else
    notify "Error: transcription file missing or empty"
  fi

  rm -f "$TMP_WAV" "$OUTPUT_FILE"
  exit 0
fi

# --- First press: start recording ---
notify "Now listening for VoxTyper"
arecord -f cd -c 1 -t wav "$TMP_WAV" &
