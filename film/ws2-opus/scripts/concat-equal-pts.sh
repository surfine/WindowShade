#!/bin/bash
# T11-01：分塊解碼後每源幀等長 1/fps 秒重包。禁止 -c copy（會把塊尾幀拉長）。
set -euo pipefail
FPS="${FPS:-30}"
if [ "$#" -lt 2 ]; then
  echo "usage: FPS=30 concat-equal-pts.sh out.mp4 part1.mp4 [part2.mp4 ...]" >&2
  exit 2
fi
out="$1"; shift
list=$(mktemp)
trap 'rm -f "$list"' EXIT
for f in "$@"; do
  printf "file '%s'\n" "$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$f")" >> "$list"
done
has_a=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$1" || true)
args=(-y -f concat -safe 0 -i "$list" -vf "setpts=N/${FPS}/TB" -r "$FPS" -c:v libx264 -crf 18 -pix_fmt yuv420p)
if [ -n "$has_a" ]; then
  args+=(-c:a aac -b:a 320k -ar 48000)
else
  args+=(-an)
fi
ffmpeg "${args[@]}" "$out"
