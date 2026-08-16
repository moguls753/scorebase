"""Bestimmt den tatsächlichen Importumfang: Gesamtzahl der Produkte und
Anteil echter Noten nach `custom.texts.itemtype`.

Belegt tools/stretta-api-evidence-2026-08-14.md §10.

    python3 tools/scripts/stretta_scope.py [stichprobe_pro_datei] [anzahl_dateien]

Die Sitemap ist nach Produktfamilien geclustert. Deshalb wird aus VIELEN
Dateien wenig gezogen statt aus wenigen viel — sonst ist die effektive
Stichprobengröße die Zahl der Cluster, nicht die der Produkte.
"""

import collections
import json
import random
import re
import sys
import time

from stretta_api import fetch, gql

SITEMAP_INDEX = "https://www.stretta-music.de/sitemap.xml"
CHILD = "https://www.stretta-music.de/sitemap/articles/%d.xml"
SEED = 2026
BATCH = 20

# Warengruppen, die als Noten gelten. Präfix-Vergleich, weil itemtype
# zusammengesetzt vorkommt ("Partitur, Stimmen", "Einzelstimme Trompete 1").
SHEET_MUSIC_PREFIXES = (
    "partitur", "chorpartitur", "klavierauszug", "studienpartitur", "spielpartitur",
    "noten", "notenbuch", "chorbuch", "einzelstimme", "stimme", "stimmen",
    "harmoniestimmen", "orchesterstimme", "klavierpartitur", "einzelausgabe",
    "lehrbuch", "realbook", "orgelauszug",
)
NON_SHEET_PREFIXES = ("buch", "cd", "playback", "dvd", "zubeh", "software")


def classify(itemtype):
    value = (itemtype or "").strip().lower()
    if not value or value == "none":
        return "ohne itemtype"
    for prefix in NON_SHEET_PREFIXES:
        if value.startswith(prefix):
            return "keine Noten"
    for prefix in SHEET_MUSIC_PREFIXES:
        if value.startswith(prefix):
            return "Noten"
    return "unklar"


def child_indexes():
    xml = fetch(SITEMAP_INDEX)
    return sorted(int(m) for m in re.findall(r"/sitemap/articles/(\d+)\.xml", xml))


def main():
    per_file = int(sys.argv[1]) if len(sys.argv) > 1 else 15
    n_files = int(sys.argv[2]) if len(sys.argv) > 2 else 40

    random.seed(SEED)
    indexes = child_indexes()
    print("articles-Kinddateien laut Index: %d" % len(indexes))

    first = len(re.findall(r"<loc>", fetch(CHILD % indexes[0])))
    last = len(re.findall(r"<loc>", fetch(CHILD % indexes[-1])))
    total = (len(indexes) - 1) * first + last
    print("  URLs in erster Datei: %d, in letzter: %d" % (first, last))
    print("  → Produkte gesamt: %d" % total)

    chosen = random.sample(indexes, min(n_files, len(indexes)))
    ids = []
    for index in chosen:
        try:
            found = re.findall(r"-nr-(\d+)\.html", fetch(CHILD % index))
        except Exception as error:
            print("  Datei %d nicht abrufbar: %s" % (index, error))
            continue
        ids += random.sample(found, min(per_file, len(found)))
    ids = list(dict.fromkeys(ids))
    print("\nStichprobe: %d Produkte aus %d Dateien" % (len(ids), len(chosen)))

    buckets = collections.Counter()
    itemtypes = collections.Counter()
    missing = 0
    for start in range(0, len(ids), BATCH):
        chunk = ids[start:start + BATCH]
        selection = "".join(
            'h%s:product(handle:"%s"){ metafield(namespace:"custom",key:"texts"){value} } '
            % (handle, handle) for handle in chunk
        )
        data = gql("{ %s }" % selection).get("data", {})
        for handle in chunk:
            product = data.get("h" + handle)
            if not product or not product.get("metafield"):
                missing += 1
                continue
            itemtype = (json.loads(product["metafield"]["value"]).get("itemtype") or "").strip()
            itemtypes[itemtype[:38] or "(leer)"] += 1
            buckets[classify(itemtype)] += 1
        time.sleep(0.05)

    checked = sum(buckets.values())
    print("nicht auffindbar: %d   geprüft: %d\n" % (missing, checked))
    for name, count in buckets.most_common():
        print("  %-16s %4d  %5.1f%%" % (name, count, 100.0 * count / checked))

    share = buckets["Noten"] / checked
    print("\nNotenanteil: %.1f%%  →  hochgerechnet %s importierbare Zeilen"
          % (100 * share, format(int(total * share), ",d").replace(",", ".")))
    print("\nHäufigste itemtypes:")
    for name, count in itemtypes.most_common(20):
        print("  %-40s %d" % (name, count))


if __name__ == "__main__":
    main()
