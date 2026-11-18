#!/bin/bash
# Claude Voice recorder: always uses the MacBook's built-in microphone, never the AirPods
# (opening the AirPods mic switches them to "call mode" and ruins the music).
DIR="$HOME/.claude-voice"
SOX=""; for b in /opt/homebrew/bin /usr/local/bin; do [ -x "$b/sox" ] && SOX="$b/sox"; done
rm -f "$DIR/in.wav"
DEV=$(cat "$DIR/mic.txt" 2>/dev/null)
if [ -z "$DEV" ]; then
  # the built-in input device, found once and remembered (e.g. "MacBook Pro Microphone")
  DEV=$(system_profiler SPAudioDataType 2>/dev/null | awk '/^        [^ ].*:$/{n=$0; sub(/^ +/,"",n); sub(/:$/,"",n); inp=0} /Input Channels/{inp=1} /Transport: Built-in/{ if (inp){ print n; exit } }')
  [ -n "$DEV" ] && echo "$DEV" > "$DIR/mic.txt"
fi
if [ -n "$DEV" ]; then
  "$SOX" -q -t coreaudio "$DEV" -c 1 -r 16000 -b 16 "$DIR/in.wav" &
  PID=$!; sleep 0.4
  if ! kill -0 $PID 2>/dev/null; then rm -f "$DIR/mic.txt"; "$SOX" -q -d -c 1 -r 16000 -b 16 "$DIR/in.wav" & PID=$!; fi
else
  "$SOX" -q -d -c 1 -r 16000 -b 16 "$DIR/in.wav" & PID=$!
fi
echo $PID > "$DIR/rec.pid"
wait
exit 0
