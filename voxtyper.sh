#!/usr/bin/env bash

# VoxTyper 0.5.0 — offline push-to-talk dictation (X11/Wayland)
# Uses whisper.cpp (whisper-cli) and selects the best available tools at
# runtime: parecord/pw-record/arecord for capture, wtype/xdotool/ydotool
# for typing into the focused window, wl-copy/xclip for the clipboard.

# --- Config ---
export PATH="$HOME/.local/bin:$HOME/.guix-home/profile/bin:/run/current-system/profile/bin:/usr/sbin:/usr/bin:$PATH"

MODEL="${HOME}/.local/share/whisper/ggml-base.bin"
WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"

# Per-invocation state lives in XDG_RUNTIME_DIR when available (tmpfs,
# per-user permissions, cleaned at logout) and falls back to ~/.cache so
# we do not share /tmp paths with other users or with root-owned files
# left over from sessions run under sudo.
RUNTIME_DIR="${XDG_RUNTIME_DIR:-${HOME}/.cache/voxtyper}"
mkdir -p "$RUNTIME_DIR"

TMP_WAV="${RUNTIME_DIR}/voxtyper-record.wav"
TMP_PREFIX="${RUNTIME_DIR}/voxtyper-output"
OUTPUT_FILE="${TMP_PREFIX}.txt"
STATE_FILE="${RUNTIME_DIR}/voxtyper.state"
LOCK_FILE="${RUNTIME_DIR}/voxtyper.lock"
DEBUG_LOG="${RUNTIME_DIR}/voxtyper-debug.log"

# KDE Plasma sometimes fires global shortcuts on both key-down and key-up.
# A second invocation arriving within this many seconds of the first is
# treated as a spurious key-up and ignored so the recording continues.
DEBOUNCE_SECONDS=2

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$DEBUG_LOG"; }

# --- Notifications ---
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

# --- Mutex via PID file ---
# We use a PID file rather than flock(1) because the recorder is
# backgrounded; the child would inherit the locked fd and keep the lock
# alive until the recorder exits, breaking the next invocation.
if [[ -f "$LOCK_FILE" ]]; then
  lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    log "Lock held by PID $lock_pid; another instance is running"
    exit 0
  fi
  log "Stale lock from dead PID $lock_pid; cleaning up"
  rm -f "$LOCK_FILE" "$STATE_FILE" "$TMP_WAV" "$OUTPUT_FILE"
fi
printf '%s\n' "$$" > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log "=== VoxTyper invoked (PID $$) ==="

# --- Second press: stop recording and transcribe ---
if [[ -f "$STATE_FILE" ]]; then
  read -r rec_pid started_ts < "$STATE_FILE" || { rec_pid=0; started_ts=0; }
  now=$(date +%s)
  elapsed=$((now - started_ts))

  if (( elapsed < DEBOUNCE_SECONDS )); then
    log "Debounce (${elapsed}s) ignoring key release"
    exit 0
  fi

  rm -f "$STATE_FILE"

  if [[ -n "$rec_pid" ]] && (( rec_pid > 0 )) && kill -0 "$rec_pid" 2>/dev/null; then
    kill -INT "$rec_pid" 2>/dev/null || true
  else
    # Fallback for state files written by older versions or where the
    # PID was lost: signal any known recorder by name.
    for rec in parecord pw-record arecord; do
      pkill -INT -x "$rec" 2>/dev/null || true
    done
  fi

  notify "Stopped VoxTyper — transcribing..."
  log "Stop received; running $WHISPER_BIN"

  # Give the recorder a moment to finalize the WAV header.
  sleep 0.3

  if [[ ! -f "$MODEL" ]]; then
    notify "Model not found: $MODEL"
    exit 1
  fi
  if ! command -v "$WHISPER_BIN" >/dev/null 2>&1; then
    notify "Whisper CLI '$WHISPER_BIN' not found (set WHISPER_BIN)"
    exit 1
  fi

  "$WHISPER_BIN" -m "$MODEL" -f "$TMP_WAV" -otxt -of "$TMP_PREFIX" --language auto \
    >> "$DEBUG_LOG" 2>&1

  if [[ -s "$OUTPUT_FILE" ]]; then
    text="$(tr '\n' ' ' < "$OUTPUT_FILE" | sed 's/[[:space:]]\+/ /g')"
    log "Transcribed ${#text} chars"

    # Always copy to clipboard first, so paste is a reliable fallback
    # even if the typing tool refuses to send synthetic input.
    if command -v wl-copy >/dev/null 2>&1; then
      printf '%s' "$text" | wl-copy
    elif command -v xclip >/dev/null 2>&1; then
      printf '%s' "$text" | xclip -selection clipboard
    fi

    # Try typing tools in order: wtype is Wayland-native and needs no
    # daemon; xdotool is the X11 standard; ydotool is the Wayland
    # alternative for compositors that do not implement the
    # virtual-keyboard protocol that wtype uses.
    typed=false
    if command -v wtype >/dev/null 2>&1; then
      printf '%s' "$text" | wtype - 2>/dev/null && typed=true
      log "wtype: $([[ $typed = true ]] && echo ok || echo failed)"
    fi
    if [[ $typed = false ]] && command -v xdotool >/dev/null 2>&1; then
      xdotool type "$text" 2>/dev/null && typed=true
      log "xdotool: $([[ $typed = true ]] && echo ok || echo failed)"
    fi
    if [[ $typed = false ]] && command -v ydotool >/dev/null 2>&1; then
      ydotool type "$text" 2>/dev/null && typed=true
      log "ydotool: $([[ $typed = true ]] && echo ok || echo failed)"
    fi

    if [[ $typed = false ]]; then
      notify "Could not type into focused window — text is on the clipboard"
    fi
  else
    log "No output from $WHISPER_BIN"
    notify "Error: transcription file missing or empty"
  fi

  rm -f "$TMP_WAV" "$OUTPUT_FILE"
  exit 0
fi

# --- First press: start recording ---
if [[ ! -f "$MODEL" ]]; then
  notify "Model not found: $MODEL"
  exit 1
fi

notify "Now listening for VoxTyper"

# Audio backend selection. Whisper resamples to 16 kHz mono internally,
# so capturing at that rate directly avoids a runtime resample and keeps
# the WAV small. parecord (PulseAudio) and pw-record (PipeWire) talk to
# the audio server directly; arecord goes through ALSA and is the last
# resort because on hosts where PulseAudio or PipeWire owns the device
# it can fail or produce a zero-byte WAV.
rec_pid=0
if command -v parecord >/dev/null 2>&1; then
  parecord --channels=1 --rate=16000 "$TMP_WAV" >> "$DEBUG_LOG" 2>&1 &
  rec_pid=$!
  log "Recording with parecord (PID $rec_pid)"
elif command -v pw-record >/dev/null 2>&1; then
  pw-record --channels=1 --rate=16000 "$TMP_WAV" >> "$DEBUG_LOG" 2>&1 &
  rec_pid=$!
  log "Recording with pw-record (PID $rec_pid)"
elif command -v arecord >/dev/null 2>&1; then
  arecord -f S16_LE -c 1 -r 16000 -t wav "$TMP_WAV" >> "$DEBUG_LOG" 2>&1 &
  rec_pid=$!
  log "Recording with arecord (PID $rec_pid)"
fi

if (( rec_pid == 0 )); then
  notify "No audio capture tool found (parecord, pw-record, or arecord)"
  exit 1
fi

printf '%s %s\n' "$rec_pid" "$(date +%s)" > "$STATE_FILE"
