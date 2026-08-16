"""Misst die Präzision der verworfenen Gruppierung über den Bestellnummern-Stamm.

Belegt Abschnitt 5 von tools/stretta-api-evidence-2026-08-14.md (Ergebnis: 24 %).

Bekannte Schwäche, bewusst unverändert gelassen, damit die berichtete Zahl
reproduzierbar bleibt: normalize_title() schneidet am ersten Komma ab und ist
damit zu aggressiv. Die 24 % sind eher Ober- als Untergrenze.

    python3 tools/scripts/stretta_ordernumber_precision.py
"""

import collections
import json
import re
import unicodedata

from stretta_api import paginate

VENDOR = "Carus Verlag"
LIMIT = 1000

QUERY = """
{ products(first:%%(first)d, query:"vendor:'%s'"%%(after)s) {
    pageInfo { hasNextPage endCursor }
    nodes { handle title metafields(identifiers:[{namespace:"custom",key:"order_no"}]) { key value } }
} }
""" % VENDOR


def stem(order_no):
    match = re.match(r"^(.*?)/(\w+)$", re.sub(r"\s+", " ", order_no.strip()))
    if not match:
        return None
    return re.sub(r"(\D)0+(\d)", r"\1\2", match.group(1))  # CV 02.170 -> CV 2.170


def normalize_title(title):
    title = (title or "").split(",")[0]
    title = re.sub(r"^\d+:\s*", "", title)
    title = re.sub(r"^(DL|AQ):\s*", "", title)
    title = re.sub(r"^[^:]{1,28}:\s*", "", title)
    title = unicodedata.normalize("NFKD", title.lower()).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", " ", title).strip()


def main():
    nodes = paginate(QUERY, max_items=LIMIT)
    print("Produkte: %d" % len(nodes))

    by_stem = collections.defaultdict(list)
    no_order = no_suffix = 0
    for node in nodes:
        fields = {f["key"]: f["value"] for f in node["metafields"] if f}
        order_no = fields.get("order_no")
        if not order_no:
            no_order += 1
            continue
        key = stem(order_no)
        if not key:
            no_suffix += 1
            continue
        by_stem[key].append(node)

    multi = {k: v for k, v in by_stem.items() if len(v) > 1}
    pure = sum(1 for group in multi.values() if len({normalize_title(n["title"]) for n in group}) == 1)

    print("ohne order_no: %d   ohne /Suffix: %d" % (no_order, no_suffix))
    print("Stämme: %d   davon mehrgliedrig: %d" % (len(by_stem), len(multi)))
    print("  ein Werktitel (echte Gruppe): %d  (%.0f%%)" % (pure, 100.0 * pure / max(1, len(multi))))
    print("  mehrere Titel (Reihe, falsch): %d" % (len(multi) - pure))

    print("\nGegenbeispiele (mehrgliedrig, verschiedene Werke):")
    shown = 0
    for key, group in multi.items():
        if len({normalize_title(n["title"]) for n in group}) == 1:
            continue
        print("  %s" % key)
        for node in group[:4]:
            print("     %s" % node["title"][:74])
        shown += 1
        if shown >= 4:
            break


if __name__ == "__main__":
    main()
