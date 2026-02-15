#!/usr/bin/env bash
set -euo pipefail

################################################################################
# albumart_16x9.sh (Linux CLI / Mint 21.3 friendly)
#
# What it does:
#   - Builds a 1920x1080 image:
#       * Background: blurred upscale fill from cover art
#       * Foreground: centered cover art at a STANDARD size (default 800x800)
#       * Text overlay from audio tags (mediainfo preferred; ffprobe fallback)
#
# Key behaviors:
#   - Foreground art standardized to ART_SIZE (default 800x800)
#     NOTE: "\>" prevents upscaling smaller covers (it will only downscale).
#   - mediainfo parsing preserves values containing ": " (e.g. "Godzilla: The Album")
#   - Layout modes:
#       --layout side (default): text block in left blurred margin
#       --layout top           : title bar above + album/year bar below the art
#
# New in this version:
#   - Optional album-art outline for dark covers:
#       --outline 2px   (or --outline 2)
#     This draws a thin border around the *foreground* art, so it sits on top of
#     the background blur/fade (and does NOT get blended into it).
#
# Usage:
#   ./albumart_16x9.sh [--layout side|top] [--art 800] [--outline 2px] <audio_file> [cover_image] [output_png]
#
# Examples:
#   ./albumart_16x9.sh --layout side --art 800 "song.opus" cover.jpg out.png
#   ./albumart_16x9.sh --layout top  --art 800 "song.opus" cover.jpg out.png
#   ./albumart_16x9.sh --layout top  --art 800 --outline 2px "song.opus" cover.jpg out.png
#   ./albumart_16x9.sh "song.opus" out.png        # attempts embedded cover extraction
################################################################################


################################################################################
# 0) Parse options + positional args
################################################################################
LAYOUT="side"       # side|top
ART_SIZE=800        # standardized foreground size
TOP_BAR_H=100       # used in top layout
BOT_BAR_H=100       # used in top layout
SIDE_PAD=20         # margin padding for side layout
SIDE_BOX_H=400      # side text area height (tweakable)

# Optional outline thickness in pixels (0 = off)
OUTLINE_PX=0

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --layout)
      LAYOUT="${2:-side}"; shift 2;;
    --art)
      ART_SIZE="${2:-800}"; shift 2;;
    --outline)
      # Accept "2" or "2px" (strip non-digits)
      val="${2:-0}"
      shift 2
      OUTLINE_PX="$(echo "$val" | sed 's/[^0-9]//g')"
      OUTLINE_PX="${OUTLINE_PX:-0}"
      ;;
    --topbar)
      TOP_BAR_H="${2:-100}"; shift 2;;
    --bottombar)
      BOT_BAR_H="${2:-100}"; shift 2;;
    --sidepad)
      SIDE_PAD="${2:-20}"; shift 2;;
    --sideh)
      SIDE_BOX_H="${2:-400}"; shift 2;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1;;
    *)
      args+=("$1"); shift;;
  esac
done

AUDIO="${args[0]:-}"
ARG2="${args[1]:-}"
ARG3="${args[2]:-}"

if [[ -z "${AUDIO}" ]]; then
  echo "Usage: $0 [--layout side|top] [--art 800] [--outline 2px] <audio_file> [cover_image] [output_png]"
  exit 1
fi

COVER_IN=""
OUT="out.png"

# If 2 positional args: treat arg2 as cover if it looks like an image, else output
if [[ -n "${ARG2}" && -z "${ARG3}" ]]; then
  case "${ARG2,,}" in
    *.png|*.jpg|*.jpeg|*.webp|*.tif|*.tiff) COVER_IN="${ARG2}";;
    *) OUT="${ARG2}";;
  esac
elif [[ -n "${ARG2}" && -n "${ARG3}" ]]; then
  COVER_IN="${ARG2}"
  OUT="${ARG3}"
fi

if [[ "${LAYOUT}" != "side" && "${LAYOUT}" != "top" ]]; then
  echo "Error: --layout must be 'side' or 'top' (got: ${LAYOUT})" >&2
  exit 1
fi


################################################################################
# 1) Dependency checks
################################################################################
for bin in magick ffprobe ffmpeg fc-match; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Error: '$bin' not found in PATH."; exit 1; }
done


################################################################################
# 2) Temp workspace
################################################################################
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cover_png="${tmpdir}/cover_in.png"


################################################################################
# 3) Acquire cover art
#    - If a cover image is provided: use it (auto-orient)
#    - Else: attempt to extract embedded cover art from the audio
################################################################################
if [[ -n "${COVER_IN}" ]]; then
  [[ -f "${COVER_IN}" ]] || { echo "Error: cover image not found: ${COVER_IN}"; exit 1; }
  magick "${COVER_IN}" -auto-orient "${cover_png}"
else
  # Extract first video stream frame as cover (common: attached_pic)
  if ffmpeg -hide_banner -loglevel error -y -i "${AUDIO}" -map 0:v:0 -frames:v 1 "${cover_png}" 2>/dev/null; then
    :
  else
    echo "Error: No cover image provided and failed to extract embedded cover from audio."
    exit 1
  fi
fi


################################################################################
# 4) Read tags from audio (mediainfo preferred; ffprobe fallback)
#
# Fix for truncation:
#   - Do NOT split lines on ": " and take $2, because values may contain ": "
#   - Instead, remove everything up to the FIRST ": " and keep the rest.
################################################################################
sanitize() { echo "$1" | tr -d '\r' | sed 's/[[:cntrl:]]//g'; }

strip_first_colon_space() {
  # Removes everything up to and including the first ": "
  # Example: "Album : Godzilla: The Album" -> "Godzilla: The Album"
  sed 's/^[^:]*:[[:space:]]*//'
}

ARTIST=""
TITLE=""
ALBUM=""
YEAR=""

read_tags_mediainfo() {
  local mi
  mi="$(mediainfo "$AUDIO" 2>/dev/null || true)"
  [[ -n "$mi" ]] || return 1

  ARTIST="$(echo "$mi" | sed -n '/^Performer[[:space:]]*:/p' | head -n1 | strip_first_colon_space | head -n1)"
  TITLE="$( echo "$mi" | sed -n '/^Track name[[:space:]]*:/p' | head -n1 | strip_first_colon_space | head -n1)"
  ALBUM="$( echo "$mi" | sed -n '/^Album[[:space:]]*:/p'      | head -n1 | strip_first_colon_space | head -n1)"
  YEAR="$(  echo "$mi" | sed -n '/^Recorded date[[:space:]]*:/p' | head -n1 | strip_first_colon_space | head -n1)"

  # Fallback labels if needed
  [[ -n "$ARTIST" ]] || ARTIST="$(echo "$mi" | sed -n '/^Artist[[:space:]]*:/p' | head -n1 | strip_first_colon_space | head -n1)"
  [[ -n "$YEAR"   ]] || YEAR="$(  echo "$mi" | sed -n '/^Year[[:space:]]*:/p'   | head -n1 | strip_first_colon_space | head -n1)"

  ARTIST="$(sanitize "${ARTIST:-}")"
  TITLE="$(sanitize "${TITLE:-}")"
  ALBUM="$(sanitize "${ALBUM:-}")"
  YEAR="$(sanitize "${YEAR:-}")"

  # Keep only a 4-digit year if present
  if [[ -n "$YEAR" ]]; then
    YEAR="$(echo "$YEAR" | sed -n 's/.*\([0-9]\{4\}\).*/\1/p' | head -n1)"
  fi

  return 0
}

dump_ffprobe_tags() {
  # Read both container(format) tags + stream(0:a:0) tags; Ogg/Opus often uses stream tags.
  local f1 f2
  f1="$(ffprobe -v error -show_entries format_tags -of default=nw=1 "$AUDIO" 2>/dev/null || true)"
  f2="$(ffprobe -v error -select_streams a:0 -show_entries stream_tags -of default=nw=1 "$AUDIO" 2>/dev/null || true)"
  printf "%s\n%s\n" "$f1" "$f2" | sed '/^$/d'
}

get_tag_ci_from_dump() {
  # Case-insensitive KEY=VALUE lookup
  local key="$1"
  local dump="$2"
  echo "$dump" | awk -F'=' -v k="$key" '
    BEGIN{IGNORECASE=1}
    $1==k {sub(/^[^=]*=/,""); print $2; exit}
  '
}

get_any_tag() {
  # Try multiple candidate keys until one hits
  local dump="$1"; shift
  local k v
  for k in "$@"; do
    v="$(get_tag_ci_from_dump "$k" "$dump" || true)"
    if [[ -n "${v}" ]]; then
      echo "$(sanitize "$v")"
      return 0
    fi
  done
  echo ""
  return 1
}

# Prefer mediainfo if present
if command -v mediainfo >/dev/null 2>&1; then
  read_tags_mediainfo || true
fi

# Fall back to ffprobe if mediainfo didn't populate anything
if [[ -z "${ARTIST}${TITLE}${ALBUM}${YEAR}" ]]; then
  TAG_DUMP="$(dump_ffprobe_tags)"
  ARTIST="$(get_any_tag "$TAG_DUMP" artist performer album_artist "album artist" || true)"
  TITLE="$( get_any_tag "$TAG_DUMP" title trackname "track name" track || true)"
  ALBUM="$( get_any_tag "$TAG_DUMP" album "album title" || true)"
  YEAR_RAW="$(get_any_tag "$TAG_DUMP" year date recorded_date "recorded date" || true)"
  YEAR=""
  if [[ -n "$YEAR_RAW" ]]; then
    YEAR="$(echo "$YEAR_RAW" | sed -n 's/.*\([0-9]\{4\}\).*/\1/p' | head -n1)"
  fi
fi

# Final fallbacks
ARTIST="${ARTIST:-Unknown Artist}"
TITLE="${TITLE:-Unknown Title}"
ALBUM="${ALBUM:-}"
YEAR="${YEAR:-}"


################################################################################
# 5) Font resolution (use font FILE paths; avoids IM family-name ambiguity)
################################################################################
FONT_REG="$(fc-match -f '%{file}\n' 'Dancing Script:style=Regular' 2>/dev/null | head -n1 || true)"
FONT_BOLD="$(fc-match -f '%{file}\n' 'Dancing Script:style=Bold' 2>/dev/null | head -n1 || true)"
FONT_FALLBACK="$(fc-match -f '%{file}\n' 'DejaVu Sans' 2>/dev/null | head -n1 || true)"

[[ -f "${FONT_REG:-}" ]] || FONT_REG="${FONT_FALLBACK}"
[[ -f "${FONT_BOLD:-}" ]] || FONT_BOLD="${FONT_REG}"

if [[ -z "${FONT_REG}" || ! -f "${FONT_REG}" ]]; then
  echo "Error: Could not resolve any usable font file."
  exit 1
fi


################################################################################
# 6) Scaling filter heuristic (unique colors proxy)
#    - Low colors (logos/flat art): Mitchell (less ringing)
#    - High colors (photo-ish):     Lanczos (sharper)
################################################################################
COLORS="$(magick "${cover_png}" -format "%k" info:)"
FILTER="Lanczos"
if [[ "${COLORS}" -le 1024 ]]; then
  FILTER="Mitchell"
fi


################################################################################
# 7) Build foreground + background images
#
# Foreground:
#   - STANDARD size ART_SIZE x ART_SIZE
#   - IMPORTANT: "\>" prevents upscaling smaller covers
#
# Background:
#   - Fill/crop to 1920x1080, then blur + darken slightly for readability
#
# Outline option:
#   - If --outline Npx is provided (N > 0), we add a thin border around the
#     *foreground art* AFTER it is built. This ensures the border is drawn on
#     top of the background blur/fade (not blended into it).
################################################################################
fg="${tmpdir}/fg.png"
bg="${tmpdir}/bg.png"

magick "${cover_png}" -filter "${FILTER}" -resize "${ART_SIZE}x${ART_SIZE}\>" \
  -background none -gravity center -extent "${ART_SIZE}x${ART_SIZE}" "${fg}"

# Optional foreground outline for dark covers (e.g. --outline 2px)
if [[ "${OUTLINE_PX}" -gt 0 ]]; then
  outlined_fg="${tmpdir}/fg_outlined.png"
  magick "${fg}" -bordercolor white -border "${OUTLINE_PX}" "${outlined_fg}"
  fg="${outlined_fg}"
fi

magick "${cover_png}" -filter "${FILTER}" -resize 1920x1080^ \
  -gravity center -extent 1920x1080 \
  -blur 0x28 -brightness-contrast -10x-5 "${bg}"


################################################################################
# 8) Text rendering helpers
#
# render_text_box:
#   - Uses caption: to wrap within a box
#   - Adds a subtle shadow for readability over blurred background
#
# measure_text_width:
#   - Measures rendered width for deciding single vs multi line in side layout
################################################################################
render_text_box() {
  # Args: out_png width height font_file pointsize text(with \n)
  local out="$1" w="$2" h="$3" font="$4" pts="$5" text="$6"

  magick -size "${w}x${h}" -background none \
    -font "${font}" -pointsize "${pts}" -fill white -gravity center \
    -interline-spacing 6 -kerning 1 \
    "caption:${text}" \
    -alpha set \
    \( +clone -background black -shadow 60x3+0+3 \) +swap -background none -layers merge +repage \
    "${out}"

  [[ -s "${out}" ]] || return 1
}

measure_text_width() {
  local text="$1" pts="$2"
  local outimg="${tmpdir}/measure.png"

  magick -background none -fill white -font "${FONT_BOLD}" -pointsize "${pts}" \
    -gravity northwest "label:${text}" -trim +repage "${outimg}" 2>/dev/null || return 1

  magick identify -format "%w" "${outimg}" 2>/dev/null
}


################################################################################
# 9A) SIDE layout (default)
#
# With ART_SIZE=800:
#   - left margin = (1920 - 800)/2 = 560
#   - safe width  = 560 - 2*SIDE_PAD = 520 (with SIDE_PAD=20)
#
# Behavior:
#   - If "Artist: Title" fits: use it (single-line style)
#   - Else: multi-line and drop ":" after artist
################################################################################
do_layout_side() {
  local margin=$(( (1920 - ART_SIZE) / 2 ))
  local box_w=$(( margin - 2*SIDE_PAD ))
  local box_h="${SIDE_BOX_H}"
  local pts=46

  local line2=""
  if [[ -n "${ALBUM}" && -n "${YEAR}" ]]; then
    line2="[${ALBUM}] (${YEAR})"
  elif [[ -n "${ALBUM}" ]]; then
    line2="[${ALBUM}]"
  elif [[ -n "${YEAR}" ]]; then
    line2="(${YEAR})"
  fi

  local text_single="${ARTIST}: ${TITLE}"
  [[ -n "${line2}" ]] && text_single="${text_single}\n${line2}"

  local w_single
  w_single="$(measure_text_width "${ARTIST}: ${TITLE}" "${pts}" || echo 99999)"

  local text_final
  if [[ "${w_single}" -le "${box_w}" ]]; then
    text_final="${text_single}"
  else
    text_final="${ARTIST}\n${TITLE}"
    [[ -n "${ALBUM}" ]] && text_final="${text_final}\n[${ALBUM}]"
    [[ -n "${YEAR}"  ]] && text_final="${text_final}\n(${YEAR})"
  fi

  local text_png="${tmpdir}/text_side.png"
  render_text_box "${text_png}" "${box_w}" "${box_h}" "${FONT_BOLD}" "${pts}" "${text_final}" \
    || { echo "Error: failed to render side text box" >&2; exit 1; }

  local tx="${SIDE_PAD}"
  local ty="${SIDE_PAD}"
  echo "${text_png}|${tx}|${ty}"
}


################################################################################
# 9B) TOP layout (optional)
#
# Layout idea:
#   - Top bar:    "Artist - Title" (centered above the art)
#   - Bottom bar: Album (bold) + (Year) (regular), centered below the art
#
# Notes:
#   - Some script fonts look visually bottom-heavy even when "centered".
#     We allow a small nudge via TOP_NUDGE_Y/BOT_NUDGE_Y.
#
# Important:
#   - ImageMagick strips leading spaces in label:, so "double spaces" must be
#     implemented as a measured pixel gap between the album and year images.
################################################################################
do_layout_top() {
  local top_w=$(( ART_SIZE - 40 ))
  local bot_w=$(( ART_SIZE - 40 ))

#  local top_pts=54
  local top_pts=46
  local bot_pts=46

  local TOP_NUDGE_Y=-10
  local BOT_NUDGE_Y=16

  local top_text="${ARTIST} - ${TITLE}"

  # Render top line into a bar canvas
  local top_png="${tmpdir}/text_top.png"
  render_text_box "${top_png}" "${top_w}" "${TOP_BAR_H}" "${FONT_BOLD}" "${top_pts}" "${top_text}" \
    || { echo "Error: failed to render top text" >&2; exit 1; }

  # Bottom line pieces (Album bold, Year regular)
  local album_text="${ALBUM}"
  local year_text=""
  if [[ -n "${YEAR}" ]]; then
    year_text="(${YEAR})"
  fi

  local bot_album_png=""
  local bot_year_png=""
  local bot_group_png="${tmpdir}/text_bot_group.png"

  # If neither exists, skip bottom entirely
  if [[ -z "${album_text}${year_text}" ]]; then
    bot_group_png=""
  elif [[ -n "${album_text}" && -z "${year_text}" ]]; then
    # Only album (bold)
    bot_album_png="${tmpdir}/text_bot_album.png"
    render_text_box "${bot_album_png}" "${bot_w}" "${BOT_BAR_H}" "${FONT_BOLD}" "${bot_pts}" "${album_text}" \
      || { echo "Error: failed to render bottom album" >&2; exit 1; }
    bot_group_png="${bot_album_png}"
  elif [[ -z "${album_text}" && -n "${year_text}" ]]; then
    # Only year (regular)
    bot_year_png="${tmpdir}/text_bot_year.png"
    render_text_box "${bot_year_png}" "${bot_w}" "${BOT_BAR_H}" "${FONT_REG}" "${bot_pts}" "${year_text}" \
      || { echo "Error: failed to render bottom year" >&2; exit 1; }
    bot_group_png="${bot_year_png}"
  else
    # Album + Year:
    #   - Render tight album label (bold)
    #   - Render tight year label (regular)
    #   - Measure the width of one space at this font size, multiply by 2
    #   - Compose [Album][double-space gap][(Year)] into a tight group
    #   - Center that group on a BOT_BAR_H canvas

    # Tight album label
    bot_album_png="${tmpdir}/bot_album_label.png"
    magick -background none -fill white -font "${FONT_BOLD}" -pointsize "${bot_pts}" \
      "label:${album_text}" -trim +repage "${bot_album_png}"

    # Tight year label (NO leading spaces — they get stripped)
    bot_year_png="${tmpdir}/bot_year_label.png"
    magick -background none -fill white -font "${FONT_REG}" -pointsize "${bot_pts}" \
      "label:${year_text}" -trim +repage "${bot_year_png}"

    # Measure "double space" as pixels WITHOUT rendering whitespace-only labels.
    # We estimate one space width using width("nn") - width("n") at the same font/pt size.
    local w_n w_nn SPACE_W GAP_W
    w_n="$(magick -background none -fill white -font "${FONT_REG}" -pointsize "${bot_pts}" \
      "label:n" -trim +repage -format "%w" info:)"
    w_nn="$(magick -background none -fill white -font "${FONT_REG}" -pointsize "${bot_pts}" \
      "label:n n" -trim +repage -format "%w" info:)"

    SPACE_W=$(( w_nn - (2 * w_n) ))
    # Guard: if something weird happens, fall back to a sensible pixel gap
    if [[ "${SPACE_W}" -le 0 ]]; then SPACE_W=12; fi

    GAP_W=$(( SPACE_W * 2 ))

    # Determine group dimensions
    local aw yw gh yh gw
    aw="$(magick identify -format "%w" "${bot_album_png}")"
    yw="$(magick identify -format "%w" "${bot_year_png}")"
    gh="$(magick identify -format "%h" "${bot_album_png}")"
    yh="$(magick identify -format "%h" "${bot_year_png}")"
    if [[ "${yh}" -gt "${gh}" ]]; then gh="${yh}"; fi

    gw=$(( aw + GAP_W + yw ))

    # Compose tight group
    local bot_group_tight="${tmpdir}/bot_group_tight.png"
    magick -size "${gw}x${gh}" xc:none -alpha set \
      -draw "image Over 0,0 0,0 '${bot_album_png}'" \
      -draw "image Over $((aw + GAP_W)),0 0,0 '${bot_year_png}'" \
      "${bot_group_tight}"

    # Center tight group on a full bar canvas
    magick -size "${bot_w}x${BOT_BAR_H}" xc:none -alpha set \
      -gravity center -draw "image Over 0,0 0,0 '${bot_group_tight}'" \
      "${bot_group_png}"
  fi

  # Foreground art centered position
  local fg_x=$(( (1920 - ART_SIZE) / 2 ))
  local fg_y=$(( (1080 - ART_SIZE) / 2 ))

  # Text images are (ART_SIZE - 40) wide; offset by +20 to align with art inset
  local top_x=$(( fg_x + 20 ))
  local bot_x=$(( fg_x + 20 ))

  # Place top above art, bottom below art (nudged)
  local top_y=$(( fg_y - TOP_BAR_H + TOP_NUDGE_Y ))
  local bot_y=$(( fg_y + ART_SIZE + BOT_NUDGE_Y ))

  # Clamp
  if [[ "${top_y}" -lt 0 ]]; then top_y=0; fi
  if [[ "${bot_y}" -gt $((1080 - BOT_BAR_H)) ]]; then bot_y=$((1080 - BOT_BAR_H)); fi

  echo "${top_png}|${top_x}|${top_y}|${bot_group_png}|${bot_x}|${bot_y}"
}


################################################################################
# 9C) Optional watermark (bottom-left)
#
# If a file named ".ab_karaoke.png" exists in the current directory,
# it will be drawn in the bottom-left corner.
#
# Assumptions:
#   - Image already has correct opacity
#   - Transparent background already set
#   - No resizing performed
#   - No additional padding applied (placed exactly at bottom-left)
################################################################################
WATERMARK_FILE=".ab_karaoke.png"
WATERMARK_X=0
WATERMARK_Y=0
WATERMARK_ENABLED=0
WATERMARK_H=0

if [[ -f "${WATERMARK_FILE}" ]]; then
  WATERMARK_H="$(magick identify -format "%h" "${WATERMARK_FILE}")"
  WATERMARK_Y=$((1080 - WATERMARK_H))
  WATERMARK_ENABLED=1
fi


################################################################################
# 10) Final composite
#
# We avoid ImageMagick image-stack pitfalls by using:
#   -draw "image Over x,y w,h 'file.png'"
#
# Outline option note:
#   - If an outline is enabled, the foreground image becomes larger than
#     ART_SIZE x ART_SIZE (it grows by 2*OUTLINE_PX in each dimension).
#   - We measure the actual foreground dimensions and center accordingly.
################################################################################

# Determine actual foreground size (accounts for outline if enabled)
FG_W="$(magick identify -format "%w" "${fg}")"
FG_H="$(magick identify -format "%h" "${fg}")"

FG_X=$(( (1920 - FG_W) / 2 ))
FG_Y=$(( (1080 - FG_H) / 2 ))

cmd=( magick "${bg}" -alpha set )
cmd+=( -draw "image Over ${FG_X},${FG_Y} ${FG_W},${FG_H} '${fg}'" )

if [[ "${LAYOUT}" == "side" ]]; then
  IFS='|' read -r text_png tx ty < <(do_layout_side)
  cmd+=( -draw "image Over ${tx},${ty} 0,0 '${text_png}'" )
else
  IFS='|' read -r top_png top_x top_y bot_png bot_x bot_y < <(do_layout_top)
  cmd+=( -draw "image Over ${top_x},${top_y} 0,0 '${top_png}'" )
  if [[ -n "${bot_png}" ]]; then
    cmd+=( -draw "image Over ${bot_x},${bot_y} 0,0 '${bot_png}'" )
  fi
fi

# Watermark (if present)
if [[ "${WATERMARK_ENABLED}" -eq 1 ]]; then
  cmd+=( -draw "image Over ${WATERMARK_X},${WATERMARK_Y} 0,0 '${WATERMARK_FILE}'" )
fi

cmd+=( "${OUT}" )
"${cmd[@]}"


################################################################################
# 11) Summary output
################################################################################
echo "Wrote: ${OUT}"
echo "Layout: ${LAYOUT}"
echo "Art size: ${ART_SIZE}x${ART_SIZE} (no upscale for smaller covers)"
echo "Filter: ${FILTER} (unique colors: ${COLORS})"
echo "Font REG:  ${FONT_REG}"
echo "Font BOLD: ${FONT_BOLD}"
echo "Tags: ARTIST='${ARTIST}' TITLE='${TITLE}' ALBUM='${ALBUM}' YEAR='${YEAR}'"

# Extra visibility for outline option (helps confirm your flag is being applied)
echo "Outline: ${OUTLINE_PX}px"
