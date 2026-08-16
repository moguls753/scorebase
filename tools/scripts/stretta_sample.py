"""Stichprobe über den Stretta-Katalog: Abdeckung von custom.texts,
Verteilung von productType und itemtype.

Belegt Abschnitt 1 und 3 von tools/stretta-api-evidence-2026-08-14.md.

    python3 tools/scripts/stretta_sample.py
"""

import collections
import json
import random
import re
import time

from stretta_api import fetch, gql

SITEMAP_FILES = [0, 400, 900, 1400, 1870]
PER_FILE = 40
SEED = 42
BATCH = 20


def sample_ids():
    ids = []
    for index in SITEMAP_FILES:
        try:
            xml = fetch("https://www.stretta-music.de/sitemap/articles/%d.xml" % index)
        except Exception as error:
            print("  sitemap %d nicht abrufbar: %s" % (index, error))
            continue
        found = re.findall(r"-nr-(\d+)\.html", xml)
        ids += random.sample(found, min(PER_FILE, len(found)))
    return list(dict.fromkeys(ids))


def main():
    random.seed(SEED)
    ids = sample_ids()
    print("Stichprobe: %d IDs" % len(ids))

    product_types = collections.Counter()
    item_types = collections.Counter()
    missing = without_texts = 0

    for start in range(0, len(ids), BATCH):
        chunk = ids[start:start + BATCH]
        selection = "".join(
            'h%s:product(handle:"%s"){ productType '
            'metafield(namespace:"custom",key:"texts"){value} } ' % (handle, handle)
            for handle in chunk
        )
        data = gql("{ %s }" % selection).get("data", {})
        for handle in chunk:
            product = data.get("h" + handle)
            if not product:
                missing += 1
                continue
            product_types[product.get("productType") or "—"] += 1
            field = product.get("metafield")
            if not field:
                without_texts += 1
                continue
            try:
                texts = json.loads(field["value"])
            except ValueError:
                without_texts += 1
                continue
            item_types[(texts.get("itemtype") or "—")[:34]] += 1
        time.sleep(0.1)

    print("nicht auffindbar: %d   ohne custom.texts: %d" % (missing, without_texts))
    print("\nproductType")
    for key, count in product_types.most_common():
        print("  %-28s %d" % (key, count))
    print("\nitemtype (Top 25)")
    for key, count in item_types.most_common(25):
        print("  %-36s %d" % (key, count))


if __name__ == "__main__":
    main()
