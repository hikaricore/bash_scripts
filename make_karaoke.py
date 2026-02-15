#!/usr/bin/env python3
import argparse
import json
import re
from typing import List, Dict, Tuple, Optional
from rapidfuzz.distance import Levenshtein

WORD_RE = re.compile(r"[A-Za-z0-9']+")
TOKEN_RE = re.compile(r"[A-Za-z0-9']+|[^A-Za-z0-9']+")

def norm_word(w: str) -> str:
    w = w.strip().lower().replace("’", "'")
    # keep alnum + apostrophes
    w = re.sub(r"[^a-z0-9']+", "", w)
    return w

def parse_lyrics_lines(path: str) -> List[str]:
    lines = []
    with open(path, "r", encoding="utf-8") as f:
        for ln in f.read().splitlines():
            lines.append(ln.rstrip("\n"))
    return lines

def lyric_words_and_line_map(lines: List[str]) -> Tuple[List[str], List[int]]:
    """Flatten lyric WORD tokens, keep mapping word_index -> line_index."""
    words = []
    line_map = []
    for li, ln in enumerate(lines):
        if not ln.strip():
            continue
        for w in WORD_RE.findall(ln.replace("’", "'")):
            words.append(w)
            line_map.append(li)
    return words, line_map

def extract_whisperx_timed_words(wx: dict) -> List[Dict]:
    """
    Supports common WhisperX outputs:
      - segments[].words[] with start/end/word
      - word_segments[] with start/end/word
    """
    out = []

    if isinstance(wx, dict) and "segments" in wx:
        for seg in wx.get("segments", []):
            for w in seg.get("words", []):
                if all(k in w for k in ("word", "start", "end")):
                    out.append({"word": str(w["word"]), "start": float(w["start"]), "end": float(w["end"])})
        if out:
            return out

    if isinstance(wx, dict) and "word_segments" in wx:
        for w in wx.get("word_segments", []):
            if all(k in w for k in ("word", "start", "end")):
                out.append({"word": str(w["word"]), "start": float(w["start"]), "end": float(w["end"])})
        if out:
            return out

    raise SystemExit("No timed words found in WhisperX JSON. Expected segments[].words[] or word_segments[].")

def dp_align(a: List[str], b: List[str]) -> List[Tuple[str, Optional[int], Optional[int]]]:
    """
    DP edit alignment: a=recognized (timed) normalized tokens, b=lyric normalized tokens.
    Returns ops: ('sub'|'ins'|'del', a_index_or_None, b_index_or_None)
    """
    n, m = len(a), len(b)
    dp = [[0]*(m+1) for _ in range(n+1)]
    bt = [[None]*(m+1) for _ in range(n+1)]

    for i in range(1, n+1):
        dp[i][0] = i
        bt[i][0] = ("del", i-1, None)
    for j in range(1, m+1):
        dp[0][j] = j
        bt[0][j] = ("ins", None, j-1)

    for i in range(1, n+1):
        for j in range(1, m+1):
            cost = 0 if a[i-1] == b[j-1] else 1
            choices = [
                (dp[i-1][j] + 1, ("del", i-1, None)),
                (dp[i][j-1] + 1, ("ins", None, j-1)),
                (dp[i-1][j-1] + cost, ("sub", i-1, j-1)),
            ]
            dp[i][j], bt[i][j] = min(choices, key=lambda x: x[0])

    ops = []
    i, j = n, m
    while i > 0 or j > 0:
        op, ai, bj = bt[i][j]
        ops.append((op, ai, bj))
        if op == "del":
            i -= 1
        elif op == "ins":
            j -= 1
        else:
            i -= 1
            j -= 1
    ops.reverse()
    return ops

def distribute_times(prev_tok: Optional[Dict], next_anchor: Optional[Dict], k: int, min_dur: float) -> List[Tuple[float, float]]:
    """
    Allocate k slots between prev and next. Used for inserted lyric words that Whisper didn't recognize.
    """
    if prev_tok and next_anchor and next_anchor["start"] > prev_tok["end"]:
        a, b = prev_tok["end"], next_anchor["start"]
        gap = max(min_dur * k, b - a)
        step = gap / k
        return [(a + step*i, a + step*(i+1)) for i in range(k)]

    if prev_tok and not next_anchor:
        a = prev_tok["end"]
        return [(a + min_dur*i, a + min_dur*(i+1)) for i in range(k)]

    if next_anchor and not prev_tok:
        b = next_anchor["start"]
        a = max(0.0, b - min_dur*k)
        step = (b - a) / k
        return [(a + step*i, a + step*(i+1)) for i in range(k)]

    return [(min_dur*i, min_dur*(i+1)) for i in range(k)]

def fmt_lrc_time(t: float) -> str:
    mm = int(t // 60)
    ss = t - mm*60
    return f"{mm:02d}:{ss:05.2f}"

def fmt_ass_time(t: float) -> str:
    h = int(t // 3600)
    t -= h*3600
    m = int(t // 60)
    s = t - m*60
    return f"{h}:{m:02d}:{s:05.2f}"

def ass_escape(text: str) -> str:
    # Escape braces which are ASS override delimiters
    return text.replace("{", r"\{").replace("}", r"\}")

def build_line_token_stream(line: str) -> List[Tuple[str, bool]]:
    """
    Returns list of (token, is_word).
    Keeps punctuation and spaces as their own tokens.
    """
    toks = TOKEN_RE.findall(line.replace("’", "'"))
    out = []
    for t in toks:
        is_word = bool(WORD_RE.fullmatch(t))
        out.append((t, is_word))
    return out

def main():
    ap = argparse.ArgumentParser(description="WhisperX JSON + true lyrics -> karaoke ASS with word highlighting + optional LRC")
    ap.add_argument("--whisperx_json", required=True, help="WhisperX JSON file containing word timings")
    ap.add_argument("--lyrics_txt", required=True, help="Lyrics text file with desired line breaks")
    ap.add_argument("--out_ass", required=True, help="Output ASS karaoke subtitle file")
    ap.add_argument("--out_lrc", default=None, help="Optional output LRC file (line-timed)")
    ap.add_argument("--out_corrected_json", default=None, help="Optional output corrected timed-words JSON")
    ap.add_argument("--min_insert_dur", type=float, default=0.06, help="Min seconds per inserted (missing) word timing slot")
    ap.add_argument("--end_pad", type=float, default=0.20, help="Pad line end time in seconds")
    ap.add_argument("--style_font", default="Arial", help="ASS font")
    ap.add_argument("--style_size", type=int, default=64, help="ASS font size")
    ap.add_argument("--resx", type=int, default=1920)
    ap.add_argument("--resy", type=int, default=1080)
    args = ap.parse_args()

    wx = json.load(open(args.whisperx_json, "r", encoding="utf-8"))
    timed = extract_whisperx_timed_words(wx)
    recog_norm = [norm_word(w["word"]) for w in timed]

    lyric_lines = parse_lyrics_lines(args.lyrics_txt)
    lyric_words_raw, word_to_line = lyric_words_and_line_map(lyric_lines)
    lyric_norm = [norm_word(w) for w in lyric_words_raw]

    if not lyric_norm:
        raise SystemExit("No lyric words found. Check your lyrics txt.")

    ops = dp_align(recog_norm, lyric_norm)

    # Build corrected per-lyric-word timings
    corrected_words: List[Dict] = []
    pending_inserts: List[str] = []

    def flush_inserts(next_anchor: Optional[Dict]):
        nonlocal pending_inserts, corrected_words
        if not pending_inserts:
            return
        prev_tok = corrected_words[-1] if corrected_words else None
        slots = distribute_times(prev_tok, next_anchor, len(pending_inserts), args.min_insert_dur)
        for (a, b), tok in zip(slots, pending_inserts):
            corrected_words.append({"word": tok, "start": a, "end": b})
        pending_inserts = []

    for op, ai, bj in ops:
        if op == "ins":
            pending_inserts.append(lyric_words_raw[bj])
            continue

        next_anchor = timed[ai] if ai is not None else None
        flush_inserts(next_anchor)

        if op == "del":
            continue

        # sub/match: keep timing from recognized, swap word from lyrics
        corrected_words.append({
            "word": lyric_words_raw[bj],
            "start": float(timed[ai]["start"]),
            "end": float(timed[ai]["end"]),
        })

    flush_inserts(None)

    # Map corrected_words back to lines (by the original lyric word order)
    line_words: Dict[int, List[Dict]] = {}
    for tok, li in zip(corrected_words, word_to_line):
        line_words.setdefault(li, []).append(tok)

    # Build ASS karaoke lines: \k is centiseconds duration for each chunk (word + trailing punctuation/spaces)
    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {args.resx}
PlayResY: {args.resy}

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,{args.style_font},{args.style_size},&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,3,1,2,80,80,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    events = []
    lrc_lines = []

    for li, line in enumerate(lyric_lines):
        if not line.strip():
            if args.out_lrc:
                lrc_lines.append("")
            continue

        toks = line_words.get(li, [])
        if not toks:
            # If no timings found for this line (rare), skip it.
            continue

        start = toks[0]["start"]
        end = max(t["end"] for t in toks) + args.end_pad

        # Tokenize the original line preserving punctuation/spaces
        stream = build_line_token_stream(line)

        # Walk word tokens and attach punctuation/spaces after them into the same karaoke chunk.
        word_idx = 0
        chunks: List[Tuple[int, str]] = []  # (k_cs, text)

        cur_text = ""
        cur_k = None

        def push_chunk(k_cs: int, text: str):
            text = ass_escape(text)
            # ASS karaoke: tag applies to following text
            return f"{{\\k{k_cs}}}{text}"

        for token, is_word in stream:
            if is_word:
                # flush previous chunk
                if cur_k is not None:
                    chunks.append((cur_k, cur_text))
                # start new chunk with next word timing
                if word_idx >= len(toks):
                    # no more timings; treat as zero-ish
                    dur = args.min_insert_dur
                else:
                    dur = max(0.01, toks[word_idx]["end"] - toks[word_idx]["start"])
                cur_k = max(1, int(round(dur * 100)))  # centiseconds, min 1
                cur_text = token
                word_idx += 1
            else:
                # punctuation/space: append to current chunk if exists, else keep as leading text
                if cur_k is None:
                    # leading punctuation/space before first word (rare)
                    # create a tiny chunk so it renders
                    cur_k = 1
                    cur_text = token
                else:
                    cur_text += token

        if cur_k is not None:
            chunks.append((cur_k, cur_text))

        ass_text = "".join(push_chunk(k, txt) for k, txt in chunks)

        events.append(
            f"Dialogue: 0,{fmt_ass_time(start)},{fmt_ass_time(end)},Default,,0,0,0,,{ass_text}"
        )

        if args.out_lrc:
            lrc_lines.append(f"[{fmt_lrc_time(start)}]{line}")

    # Write ASS
    with open(args.out_ass, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("\n".join(events))
        f.write("\n")

    # Write optional LRC
    if args.out_lrc:
        with open(args.out_lrc, "w", encoding="utf-8") as f:
            f.write("\n".join(lrc_lines).rstrip() + "\n")

    # Write optional corrected JSON
    if args.out_corrected_json:
        out = {
            "source_whisperx_json": args.whisperx_json,
            "source_lyrics_txt": args.lyrics_txt,
            "words": [
                {"word": w["word"], "start": round(w["start"], 3), "end": round(w["end"], 3)}
                for w in corrected_words
            ],
        }
        with open(args.out_corrected_json, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)

    print(f"Wrote: {args.out_ass}")
    if args.out_lrc:
        print(f"Wrote: {args.out_lrc}")
    if args.out_corrected_json:
        print(f"Wrote: {args.out_corrected_json}")

if __name__ == "__main__":
    main()
