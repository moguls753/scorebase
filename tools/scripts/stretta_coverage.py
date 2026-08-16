"""Misst, wie viel von ScoreBases geklicktem freiem Repertoire Stretta abdeckt.

Erzeugt die Zahlen in tools/stretta-api-evidence-2026-08-14.md §Abdeckung
("90 % der Komponisten, 42 % der Werke").

Vorbereitung — GSC-Seitendaten holen (siehe CLAUDE.md, tools/gsc.rb):

    ruby tools/gsc.rb query --dimensions page --days 90 --filter "page~~/scores/" \
      > /tmp/gsc-pages.json

Dann:

    python3 tools/scripts/stretta_coverage.py /tmp/gsc-pages.json [storage/development.sqlite3]

WICHTIG zur Belastbarkeit: der Werkabgleich ist ein grober Nachname-plus-Stichwort-
Treffer gegen Strettas Titelsuche. Er misst RECALL, nicht Präzision, und produziert
nachweislich Fehltreffer (Amy Beach -> "The Beach Boys"). Für Match-Qualität ist eine
handgelabelte Stichprobe nötig; diese Zahl taugt nur zur Frage "lohnt der Partner".
"""

import collections
import json
import re
import sqlite3
import sys
import time

from stretta_api import gql

TOP_N = 200
NOBILIARY = {"de", "da", "del", "van", "von", "der", "di", "le", "la", "du", "dos", "des"}
STOPWORDS = set(
    """der die das und in im a an the of for on to no nr op mit aus zu es il la le los las el
    missa in d c g f e b flat major minor dur moll sonata sonate""".split()
)
CHORAL = re.compile(r"\b(GCh|Gch|Chpa|Chb|FCh|MCh|KiCh|Ch\d)", re.I)


def surname(composer):
    composer = (composer or "").strip()
    if not composer:
        return None
    part = composer.split(",")[0].strip() if "," in composer else composer
    tokens = [t for t in re.split(r"[\s.]+", part) if len(t) > 1 and t.lower() not in NOBILIARY]
    return tokens[-1] if tokens else None


def keyword(title):
    tokens = [w for w in re.split(r"[^\wÀ-ÿ]+", title or "")
              if len(w) > 3 and w.lower() not in STOPWORDS]
    return tokens[0] if tokens else None


def search(term, limit=10):
    query = '{ products(first:%d, query:%s){ nodes{ handle title } } }' % (limit, json.dumps(term))
    data = gql(query)
    return (data.get("data", {}).get("products") or {}).get("nodes") or []


def top_free_scores(gsc_path, db_path):
    rows = json.load(open(gsc_path))
    clicks = collections.Counter()
    for row in rows:
        match = re.search(r"/scores/(\d+)", row["keys"][0])
        if match:
            clicks[int(match.group(1))] += row["clicks"]

    db = sqlite3.connect(db_path)
    db.row_factory = sqlite3.Row
    info = {}
    ids = list(clicks)
    for start in range(0, len(ids), 900):
        chunk = ids[start:start + 900]
        placeholders = ",".join("?" * len(chunk))
        sql = ("select id, source, title, composer, deleted_at from scores "
               "where id in (%s)" % placeholders)
        for row in db.execute(sql, chunk):
            info[row["id"]] = dict(row)

    free = [(i, c) for i, c in clicks.items()
            if i in info and info[i]["source"] != "smd" and info[i]["deleted_at"] is None and c > 0]
    free.sort(key=lambda pair: -pair[1])
    return [dict(info[i], clicks=c) for i, c in free[:TOP_N]]


def main():
    gsc_path = sys.argv[1]
    db_path = sys.argv[2] if len(sys.argv) > 2 else "storage/development.sqlite3"

    top = top_free_scores(gsc_path, db_path)
    print("Top-%d freie Seiten nach Klicks, %d Klicks gesamt" % (len(top), sum(s["clicks"] for s in top)))

    composer_hits = work_hits = choral_hits = 0
    composer_clicks = work_clicks = 0
    for index, score in enumerate(top):
        name, word = surname(score["composer"]), keyword(score["title"])
        if name and search(name, 10):
            composer_hits += 1
            composer_clicks += score["clicks"]
        works = search("%s %s" % (name, word), 10) if name and word else []
        if works:
            work_hits += 1
            work_clicks += score["clicks"]
            if any(CHORAL.search(w["title"]) for w in works):
                choral_hits += 1
        if index % 25 == 0:
            print("  … %d/%d" % (index, len(top)), flush=True)
        time.sleep(0.03)

    total = len(top)
    print("\nKomponist bei Stretta bekannt : %3d / %d (%.0f%%)  Klicks %d"
          % (composer_hits, total, 100.0 * composer_hits / total, composer_clicks))
    print("Werk-Treffer (Nachname+Stichw): %3d / %d (%.0f%%)  Klicks %d"
          % (work_hits, total, 100.0 * work_hits / total, work_clicks))
    print("davon mit Chorausgabe         : %3d / %d (%.0f%%)"
          % (choral_hits, total, 100.0 * choral_hits / total))


if __name__ == "__main__":
    main()
