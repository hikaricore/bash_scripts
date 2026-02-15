#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

# Robust batch convert CDG+MP3 pairs to 1440x1080 (4:3) H.265 + Opus MKV
# Progress: current file % + file elapsed/ETA + overall % + batch elapsed/ETA
# Logging: WARN/FAIL + unexpected script aborts (line number)

IN_DIR="${1:-.}"
OUT_DIR="${2:-./Import}"
mkdir -p "$OUT_DIR"

command -v ffmpeg  >/dev/null || { echo "ffmpeg not found"; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found"; exit 1; }

LOG_FILE="$OUT_DIR/convert_log_$(date '+%Y%m%d_%H%M%S').log"

# Log any unexpected error with line number
#trap 'rc=$?; echo "[$(date "+%Y-%m-%d %H:%M:%S")] ABORT rc=$rc at line $LINENO" >> "$LOG_FILE"; exit $rc' ERR

fmt_hms() {
  local s="${1%.*}"
  [[ -z "$s" ]] && s=0
  (( s < 0 )) && s=0
  printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60))
}

# Collect MP3+CDG pairs safely (null-delimited)
mapfile -d '' MP3S < <(find "$IN_DIR" -maxdepth 1 -type f -iname '*.mp3' -print0 | sort -z)

declare -a BASES=()
declare -a DURS=()
TOTAL_DUR=0

for mp3 in "${MP3S[@]}"; do
  base="${mp3%.mp3}"
  cdg="${base}.cdg"
  [[ -f "$cdg" ]] || continue

  dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$mp3" 2>/dev/null || true)"
  [[ -n "${dur:-}" && "$dur" != "N/A" ]] || continue

  BASES+=("$base")
  DURS+=("$dur")

  dur_int="${dur%.*}"
  [[ -z "$dur_int" ]] && dur_int=0
  TOTAL_DUR=$((TOTAL_DUR + dur_int))
done

N="${#BASES[@]}"
if (( N == 0 )); then
  echo "No MP3+CDG pairs found in: $IN_DIR"
  exit 0
fi

echo "Found $N CDG+MP3 pairs. Output dir: $OUT_DIR"
echo "Log (WARN/FAIL/ABORT) will be written to: $LOG_FILE"
echo

BATCH_START_EPOCH="$(date +%s)"
PROCESSED_DUR=0
COMPLETED=0
WARNED=0
FAILED=0

for ((i=0; i<N; i++)); do
  base="${BASES[$i]}"
  dur="${DURS[$i]}"
  dur_int="${dur%.*}"; [[ -z "$dur_int" ]] && dur_int=0

  mp3="${base}.mp3"
  cdg="${base}.cdg"

  bn="$(basename "$base")"
  out="$OUT_DIR/${bn}_4x3_1080p.mkv"

  tmp_err="$(mktemp)"
  fifo="$(mktemp -u)"
  mkfifo "$fifo"

  FILE_START_EPOCH="$(date +%s)"

  # Start ffmpeg in background; progress written to FIFO, stderr captured
  ffmpeg -hide_banner -y \
    -max_interleave_delta 0 \
    -fflags +genpts \
    -i "$mp3" \
    -err_detect ignore_err -i "$cdg" \
    -filter_complex "\
[1:v]fps=25, \
scale=1440:1080:flags=neighbor, \
format=yuv420p, \
tpad=stop_mode=clone:stop_duration=${dur}[v]" \
    -map "[v]" -map 0:a:0 \
    -t "$dur" \
    -c:v libx265 -preset medium -crf 26 \
    -x265-params aq-mode=3 \
    -c:a libopus -b:a 192k -vbr on -compression_level 10 \
    -progress "$fifo" -nostats \
    "$out" \
    2>"$tmp_err" &
  ff_pid=$!

  # Read progress until FIFO closes
  while IFS='=' read -r k v; do
    if [[ "$k" == "out_time_ms" ]]; then
      [[ "${v:-}" =~ ^[0-9]+$ ]] || continue

      done_sec="$(awk -v m="$v" 'BEGIN{printf "%.2f", m/1000000}')"
      file_pct="$(awk -v d="$done_sec" -v t="$dur" 'BEGIN{ if(t<=0) print 0; else printf "%.1f", (d/t)*100 }')"

      now="$(date +%s)"
      file_elapsed=$((now - FILE_START_EPOCH))
      file_eta="$(awk -v e="$file_elapsed" -v p="$file_pct" 'BEGIN{ if(p<=0.1) print -1; else printf "%.0f", (e*(100-p)/p) }')"

      cur_media_done_int="${done_sec%.*}"; [[ -z "$cur_media_done_int" ]] && cur_media_done_int=0
      overall_done=$((PROCESSED_DUR + cur_media_done_int))
      batch_elapsed=$((now - BATCH_START_EPOCH))

      overall_eta="$(awk -v e="$batch_elapsed" -v d="$overall_done" -v t="$TOTAL_DUR" 'BEGIN{ if(d<=0) print -1; else printf "%.0f", (e*(t-d)/d) }')"
      overall_pct="$(awk -v d="$overall_done" -v t="$TOTAL_DUR" 'BEGIN{ if(t<=0) print 0; else printf "%.1f", (d/t)*100 }')"

      printf "\r[%d/%d | done %d | warn %d | fail %d] File: %s  %5s%%  file %s ETA %s  overall %5s%%  batch %s ETA %s" \
        "$((i+1))" "$N" "$COMPLETED" "$WARNED" "$FAILED" \
        "$bn" \
        "$file_pct" \
        "$(fmt_hms "$file_elapsed")" "$(fmt_hms "$file_eta")" \
        "$overall_pct" \
        "$(fmt_hms "$batch_elapsed")" "$(fmt_hms "$overall_eta")"
    fi
  done < "$fifo" || true

  # Close resources
  rm -f "$fifo"

  # Wait for ffmpeg; capture RC without letting it abort the script
  wait_rc=0
  wait "$ff_pid" || wait_rc=$?

  echo

  # Outcome handling:
  if [[ ! -f "$out" || ! -s "$out" ]]; then
    ((FAILED++))
    {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL (rc=$wait_rc): $bn"
      echo "  MP3: $mp3"
      echo "  CDG: $cdg"
      echo "  OUT: $out"
      echo "  --- ffmpeg stderr ---"
      sed 's/^/  /' "$tmp_err"
      echo
    } >> "$LOG_FILE"
    echo "FAILED: $bn (logged)"
  else
    ((COMPLETED++))
    if (( wait_rc != 0 )); then
      ((WARNED++))
      {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN (rc=$wait_rc): $bn (output created)"
        echo "  OUT: $out"
        echo "  --- ffmpeg stderr ---"
        sed 's/^/  /' "$tmp_err"
        echo
      } >> "$LOG_FILE"
      echo "WARN: $bn (ffmpeg rc=$wait_rc; output OK; logged)"
    fi
  fi

  PROCESSED_DUR=$((PROCESSED_DUR + dur_int))
  rm -f "$tmp_err"
done

echo
echo "Completed: $COMPLETED / $N   (WARN: $WARNED, FAIL: $FAILED)"
echo "Log written: $LOG_FILE"
