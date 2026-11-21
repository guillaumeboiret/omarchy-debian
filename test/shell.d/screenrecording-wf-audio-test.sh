#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# wf-recorder takes one audio device. With desktop and microphone audio both
# requested, wf-recorder records desktop audio and the microphone records to a
# track of its own, mixed in when the recording is finalized. A source that
# can't be recorded is left out with a notification naming it.
tmp=$(mktemp -d)
trap '[[ -s $tmp/state ]] && kill "$(head -1 "$tmp/state")" 2>/dev/null; rm -rf "$tmp"' EXIT

awk '
  /^(wf_audio_device|start_mic_track|wf_audio_unavailable|wf_audio_cleanup)\(\) \{/ { copying = 1 }
  copying { print }
  /^}/ { copying = 0 }
' "$ROOT/bin/omarchy-capture-screenrecording" >"$tmp/functions"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/pactl" <<'SH'
#!/bin/bash
echo "pactl $*" >>"$TMP/calls"
case $1 in
  get-default-sink) [[ -e $TMP/no-sink ]] || echo speakers ;;
  get-default-source) if [[ -e $TMP/no-source ]]; then echo @DEFAULT_SOURCE@; else echo mic; fi ;;
esac
SH
# pw-record exits at once when $TMP/refuse exists; otherwise it writes its file
# and records until interrupted.
cat >"$tmp/bin/pw-record" <<'SH'
#!/bin/bash
echo "pw-record $*" >>"$TMP/calls"
[[ ! -e $TMP/refuse ]] || exit 1
touch "${@: -1}"
trap 'echo stopped >>"$TMP/calls"; exit 0' INT TERM
while true; do sleep 0.05; done
SH
cat >"$tmp/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
echo "notify $*" >>"$TMP/notes"
echo "noise on stdout"
SH
chmod +x "$tmp/bin"/*

run() {
  TMP=$tmp PATH="$tmp/bin:$PATH" DESKTOP_AUDIO=${DESKTOP_AUDIO:-true} MICROPHONE_AUDIO=${MICROPHONE_AUDIO:-true} \
    MIC_STATE_FILE=$tmp/state bash -c "source \"\$TMP/functions\"; $1"
}

device() {
  rm -f "$tmp/calls" "$tmp/notes"
  DESKTOP_AUDIO=$1 MICROPHONE_AUDIO=$2 run wf_audio_device >"$tmp/out"
}

device true true
[[ $(cat "$tmp/out") == $'speakers.monitor\nmic' ]] || fail "both sources: desktop to wf-recorder, microphone to its own track" "$(cat "$tmp/out")"
[[ ! -e $tmp/notes ]] && ! grep -q load-module "$tmp/calls" || fail "a full mix notifies and loads nothing" "$(cat "$tmp/calls")"
pass "desktop audio goes to wf-recorder and the microphone to a separate track"

touch "$tmp/no-source"
device true true
[[ $(cat "$tmp/out") == speakers.monitor ]] || fail "without a default source desktop audio records alone" "$(cat "$tmp/out")"
grep -q 'notify .*microphone audio' "$tmp/notes" || fail "a missing default source is named" "$(cat "$tmp/notes" 2>/dev/null)"
device false true
[[ ! -s $tmp/out ]] && grep -q 'notify .*microphone audio' "$tmp/notes" || fail "a microphone-only recording without a source says so" "$(cat "$tmp/out")"
rm "$tmp/no-source"
pass "a requested source with no default device is named"

device true false
[[ $(cat "$tmp/out") == speakers.monitor && ! -e $tmp/notes ]] || fail "desktop audio alone records the sink monitor" "$(cat "$tmp/out")"
device false true
[[ $(cat "$tmp/out") == mic && ! -e $tmp/notes ]] || fail "microphone audio alone records the source" "$(cat "$tmp/out")"
device false false
[[ ! -s $tmp/out && ! -e $tmp/calls ]] || fail "no audio asks pactl nothing" "$(cat "$tmp/calls")"
pass "a single source records directly and no audio asks for nothing"

# A track that records is kept for finalizing on stop, and deleted on a cancel.
rm -f "$tmp/calls"
run "start_mic_track mic '$tmp/track.flac' && wf_audio_cleanup keep && echo \"\$MIC_TRACK\"" >"$tmp/out"
[[ $(cat "$tmp/out") == "$tmp/track.flac" && -e $tmp/track.flac && ! -e $tmp/state ]] ||
  fail "a stopped recording keeps its microphone track for finalizing" "$(cat "$tmp/out")"
grep -q stopped "$tmp/calls" || fail "the microphone recorder is interrupted" "$(cat "$tmp/calls")"
run "start_mic_track mic '$tmp/track.flac' && wf_audio_cleanup"
[[ ! -e $tmp/track.flac && ! -e $tmp/state ]] || fail "a cancelled recording deletes its microphone track"
pass "the microphone track is kept on stop and deleted on cancel"

touch "$tmp/refuse"
status=0
run "start_mic_track mic '$tmp/track.flac'" || status=$?
(( status == 1 )) && [[ ! -e $tmp/track.flac && ! -e $tmp/state ]] || fail "a microphone recorder that won't start leaves nothing"
rm "$tmp/refuse"
pass "a microphone recorder that won't start is reported and leaves nothing"
