#!/usr/bin/env bash

# VoxTyper: offline push-to-talk dictation (Linux, Wayland-friendly)
# Uses whisper.cpp (whisper-cli), wl-clipboard, arecord, libnotify, and ydotool.

# --- Config ---
# Multilingual Whisper model (supports --language auto).
# For stronger machines and better accuracy you can switch to:
#   ggml-small.bin, ggml-medium.bin, or ggml-large.bin
# by downloading the file into the same folder and adjusting this path.
MODEL="${HOME}/.local/share/whisper/ggml-base.bin"

# Whisper CLI binary. Override with:  WHISPER_BIN=whisper-cpp voxtyper
WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"

TMP_WAV="/tmp/whisper-record.wav"
TMP_PREFIX="/tmp/whisper-output"
OUTPUT_FILE="${TMP_PREFIX}.txt"

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "VoxTyper" "$1"
  else
    printf 'VoxTyper: %s\n' "$1"
  fi
}

# --- Second press: stop recording and transcribe ---
if pgrep -x "arecord" >/dev/null 2>&1; then
  pkill -INT arecord
  notify "Processing..."

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
    # Flatten newlines and excess whitespace
    text="$(tr '\n' ' ' < "$OUTPUT_FILE" | sed 's/[[:space:]]\+/ /g')"

    # Copy to clipboard (always)
    if command -v wl-copy >/dev/null 2>&1; then
      printf '%s' "$text" | wl-copy
    fi

    # If ydotool is available and daemon running, type into active window
    if command -v ydotool >/dev/null 2>&1; then
      ydotool type "$text"
    fi
  else
    notify "Error: transcription file missing or empty"
  fi

  rm -f "$TMP_WAV" "$OUTPUT_FILE"
  exit 0
fi

# --- First press: start recording ---
notify "Recording..."
arecord -f cd -c 1 -t wav "$TMP_WAV" &
