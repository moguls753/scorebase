#!/usr/bin/env python3
"""
Minimal chord_span extractor for backfilling missing data.

Usage:
    python3 extract_chord_span.py /path/to/score.mxl
    python3 extract_chord_span.py --batch paths.txt -o results.jsonl

Output: {"file_path": "...", "max_chord_span": 12} or {"file_path": "...", "max_chord_span": null}
"""

import json
import sys
from pathlib import Path

from music21 import chord, converter


def extract_chord_span(file_path: str) -> dict:
    """Extract only max_chord_span from a MusicXML file."""
    result = {"file_path": file_path, "max_chord_span": None}

    try:
        score = converter.parse(file_path)

        if len(score.parts) > 2:
            return result

        max_span = 0
        for part in score.parts:
            for c in part.flatten().getElementsByClass(chord.Chord):
                if len(c.pitches) >= 2:
                    pitches_sorted = sorted(c.pitches, key=lambda p: p.ps)
                    span = int(pitches_sorted[-1].ps - pitches_sorted[0].ps)
                    max_span = max(max_span, span)

        if max_span > 0:
            result["max_chord_span"] = max_span

    except Exception as e:
        result["error"] = str(e)[:200]

    return result


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Extract chord_span from MusicXML")
    parser.add_argument("path", nargs="?", help="Path to MusicXML file")
    parser.add_argument("--batch", "-b", metavar="FILE", help="Batch mode: read paths from FILE")
    parser.add_argument("--output", "-o", metavar="FILE", help="Output file (default: stdout)")

    args = parser.parse_args()

    if args.batch:
        with open(args.batch) as f:
            paths = [line.strip() for line in f if line.strip()]

        out = open(args.output, "w") if args.output else sys.stdout
        total = len(paths)

        for i, path in enumerate(paths):
            result = extract_chord_span(path)
            out.write(json.dumps(result) + "\n")
            print(f"\r  [{i+1}/{total}] {Path(path).name}", file=sys.stderr, end="")
            sys.stderr.flush()

        print(file=sys.stderr)
        if args.output:
            out.close()
    elif args.path:
        print(json.dumps(extract_chord_span(args.path)))
    else:
        parser.print_help()
