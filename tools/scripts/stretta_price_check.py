"""Prüft die gespeicherten Stretta-Preise gegen die gerenderte Produktseite und
klärt drei offene Fragen zur Storefront-API.

    python3 tools/scripts/stretta_price_check.py pages [n] [seed]  # (a) ld+json-Abgleich
    python3 tools/scripts/stretta_price_check.py context           # (b) @inContext je Land
    python3 tools/scripts/stretta_price_check.py variants [n]      # (c) minVariantPrice
    python3 tools/scripts/stretta_price_check.py basket            # (d) Warenkorbvarianten

Liest storage/stretta-sighting.sqlite3, schreibt nichts.
Hintergrund zu (a): bei SMD standen monatelang 20-40 % zu hohe Preise in der DB.
"""

import json
import os
import random
import re
import sqlite3
import sys
import time
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stretta_api import fetch, gql, metafield_identifiers  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIGHTING_DB = os.path.join(ROOT, "storage", "stretta-sighting.sqlite3")
BYTES_PER_ROW = 4096

LD_JSON = re.compile(r'<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>', re.S)


def db():
    return sqlite3.connect("file:%s?mode=ro" % SIGHTING_DB, uri=True)


def thousands(value):
    return format(int(value), ",d").replace(",", ".")


def product_url(handle, slug):
    return "https://www.stretta-music.de/%s.html" % (slug or "x-nr-%s" % handle)


def walk_json(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk_json(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk_json(value)


def page_price(html):
    """Alle offers.price aus ld+json-Blöcken vom Typ Product."""
    prices, currencies = [], set()
    for block in LD_JSON.findall(html):
        try:
            data = json.loads(block)
        except ValueError:
            continue
        for node in walk_json(data):
            types = node.get("@type")
            types = types if isinstance(types, list) else [types]
            if "Product" not in types:
                continue
            offers = node.get("offers")
            for offer in walk_json(offers) if offers else []:
                if "price" in offer:
                    try:
                        prices.append(float(offer["price"]))
                    except (TypeError, ValueError):
                        pass
                    if offer.get("priceCurrency"):
                        currencies.add(offer["priceCurrency"])
    return prices, currencies


def check_pages(count=50, seed=20260815):
    connection = db()
    rows = connection.execute(
        "SELECT handle, slug_de, price, minquantity, text_title FROM products "
        "WHERE price IS NOT NULL"
    ).fetchall()
    random.seed(seed)
    chosen = random.sample(rows, count)
    print("(a) Preisabgleich gespeichert vs. ld+json der Produktseite")
    print("    Stichprobe %d, seed %d\n" % (count, seed))

    equal = differing = unreachable = no_ld = 0
    deviations = []
    for index, (handle, slug, stored, minquantity, title) in enumerate(chosen, 1):
        url = product_url(handle, slug)
        try:
            html = fetch(url, timeout=45)
        except urllib.error.HTTPError as error:
            print("  %2d. %-9s HTTP %s  %s" % (index, handle, error.code, url))
            unreachable += 1
            continue
        except Exception as error:
            print("  %2d. %-9s %s" % (index, handle, error))
            unreachable += 1
            continue

        prices, currencies = page_price(html)
        if not prices:
            print("  %2d. %-9s kein ld+json-Product  %s" % (index, handle, url))
            no_ld += 1
            continue
        page = min(prices)
        delta = page - stored
        share = 100.0 * delta / stored if stored else 0
        flag = "gleich" if abs(delta) < 0.005 else "ABWEICHUNG"
        if abs(delta) < 0.005:
            equal += 1
        else:
            differing += 1
            deviations.append((handle, title, stored, page, share, minquantity, url))
        print("  %2d. %-9s gespeichert %8.2f  Seite %8.2f  %+7.2f (%+6.1f%%)  %-10s %s"
              % (index, handle, stored, page, delta, share, flag,
                 ",".join(sorted(currencies)) or "?"))
        time.sleep(0.15)

    total = equal + differing
    print("\n    identisch      %3d" % equal)
    print("    abweichend     %3d%s" % (differing,
          "  (%.0f%% der geprüften)" % (100.0 * differing / total) if total else ""))
    print("    ohne ld+json   %3d" % no_ld)
    print("    nicht abrufbar %3d" % unreachable)
    if deviations:
        print("\n    Abweichungen im Einzelnen:")
        for handle, title, stored, page, share, minquantity, url in deviations:
            print("      %-9s %-40s %8.2f -> %8.2f (%+.1f%%) minqty=%s"
                  % (handle, (title or "")[:40], stored, page, share, minquantity))
            print("        %s" % url)


def check_context():
    print("(b) Antwortet die Storefront-API marktabhängig? @inContext(country:)\n")
    connection = db()
    handles = [row[0] for row in connection.execute(
        "SELECT handle FROM products WHERE price>0 ORDER BY handle LIMIT 6")]
    countries = ["DE", "AT", "CH", "US", "GB", "FR", "NL"]

    print("    %-10s %s" % ("handle", "".join("%12s" % c for c in ["ohne"] + countries)))
    for handle in handles:
        cells = []
        for country in [None] + countries:
            directive = "@inContext(country: %s)" % country if country else ""
            query = ('query %s { product(handle:"%s") { priceRange '
                     '{ minVariantPrice { amount currencyCode } } } }' % (directive, handle))
            try:
                data = gql(query, retries=1, timeout=60)
            except Exception as error:
                cells.append("%12s" % type(error).__name__[:11])
                continue
            if "errors" in data:
                cells.append("%12s" % "ERROR")
                continue
            product = (data.get("data") or {}).get("product")
            if not product:
                cells.append("%12s" % "-")
                continue
            money = product["priceRange"]["minVariantPrice"]
            cells.append("%12s" % ("%s %s" % (money["amount"], money["currencyCode"])))
        print("    %-10s %s" % (handle, "".join(cells)))
    print("\n    Gleiche Werte in allen Spalten = die API antwortet marktunabhängig.")


def check_variants(count=8):
    print("(c) Liefert priceRange.minVariantPrice den zuerst sichtbaren Preis?\n")
    connection = db()
    handles = [row[0] for row in connection.execute(
        "SELECT handle FROM products WHERE price>0 ORDER BY RANDOM() LIMIT 400")]

    query_fields = """
      handle
      priceRange { minVariantPrice { amount } maxVariantPrice { amount } }
      variants(first:20) { nodes { title availableForSale price { amount } } }
    """
    multi = 0
    print("    %-9s %8s %8s %6s  %s" % ("handle", "minVar", "1.Var", "Anz", "Varianten"))
    for handle in handles:
        if multi >= count:
            break
        data = gql("{ product(handle:\"%s\") { %s } }" % (handle, query_fields),
                   retries=1, timeout=60)
        product = (data.get("data") or {}).get("product")
        if not product:
            continue
        nodes = product["variants"]["nodes"]
        if len(nodes) < 2:
            continue
        multi += 1
        low = float(product["priceRange"]["minVariantPrice"]["amount"])
        first = float(nodes[0]["price"]["amount"])
        marker = "" if abs(low - first) < 0.005 else "   <-- weicht ab"
        print("    %-9s %8.2f %8.2f %6d  %s%s"
              % (handle, low, first, len(nodes),
                 " | ".join("%s %s" % (n["title"][:18], n["price"]["amount"]) for n in nodes[:4]),
                 marker))
        time.sleep(0.05)
    if not multi:
        print("    In 400 gezogenen Produkten kein einziges mit mehr als einer Variante.")
    else:
        print("\n    %d Produkte mit mehreren Varianten gefunden." % multi)


def basket_variants(price, minquantity, bulk_prices):
    """Drei Lesarten desselben Warenkorbs."""
    if price is None:
        return None, None, None
    quantity = minquantity if minquantity and minquantity > 1 else 1
    floor = price * quantity
    tiers = None
    if bulk_prices:
        try:
            parsed = json.loads(bulk_prices)
            tiers = parsed if isinstance(parsed, list) and parsed else None
        except ValueError:
            tiers = None
    if tiers:
        def value(tier):
            try:
                return float(tier.get("amount") or 0) * float(tier.get("price") or 0)
            except (TypeError, ValueError):
                return 0.0
        values = [value(t) for t in tiers if value(t) > 0]
        highest = max(values) if values else floor
        lowest = min(values) if values else floor
    else:
        highest = lowest = floor
    return highest, lowest, floor


def check_basket():
    print("(d) expected_basket — bisherige Formel gegen zwei konservative Lesarten\n")
    print("    hoechste Staffel : amount x price der GROESSTEN Staffel (bisher gespeichert)")
    print("    niedrigste Staffel: amount x price der KLEINSTEN Staffel")
    print("    Mindestkauf      : price x max(minquantity,1) — was der Kunde zwingend zahlt\n")

    connection = db()
    rows = connection.execute(
        "SELECT price, minquantity, bulk_prices, expected_basket FROM products").fetchall()
    highest, lowest, floor = [], [], []
    mismatch = 0
    for price, minquantity, bulk, stored in rows:
        a, b, c = basket_variants(price, minquantity, bulk)
        if a is None:
            continue
        highest.append(a)
        lowest.append(b)
        floor.append(c)
        if stored is not None and abs(a - stored) > 0.01:
            mismatch += 1
    print("    Zeilen: %s   Nachrechnung weicht in %s Zeilen von der gespeicherten Spalte ab"
          % (thousands(len(highest)), thousands(mismatch)))
    print("\n    Summen:  hoechste %s EUR   niedrigste %s EUR   Mindestkauf %s EUR"
          % (thousands(sum(highest)), thousands(sum(lowest)), thousands(sum(floor))))

    print("\n    Schwellwerttabelle in drei Varianten:\n")
    print("    %-12s %26s %26s %26s"
          % ("", "hoechste Staffel", "niedrigste Staffel", "Mindestkauf"))
    print("    %-12s %12s %13s %12s %13s %12s %13s"
          % ("Schwelle", "Zeilen", "Platz", "Zeilen", "Platz", "Zeilen", "Platz"))
    for threshold in (0, 5, 10, 20, 50, 100):
        cells = []
        for series in (highest, lowest, floor):
            count = sum(1 for value in series if value >= threshold)
            cells.append("%12s %10.2f GB" % (thousands(count), count * BYTES_PER_ROW / 1024 ** 3))
        label = "alle" if threshold == 0 else ">= %d EUR" % threshold
        print("    %-12s %s" % (label, " ".join(cells)))

    print("\n    Nur die %s Zeilen mit befuellten bulk_prices:" % thousands(
        sum(1 for _, _, bulk, _ in rows if bulk and bulk not in ("", "[]"))))
    affected = [(a, b, c) for (price, minquantity, bulk, _), (a, b, c)
                in zip(rows, (basket_variants(p, m, b) for p, m, b, _ in rows))
                if bulk and bulk not in ("", "[]") and a is not None]
    if affected:
        print("      Summe hoechste  %14s EUR" % thousands(sum(a for a, _, _ in affected)))
        print("      Summe niedrigste %13s EUR" % thousands(sum(b for _, b, _ in affected)))
        print("      Summe Mindestkauf %12s EUR" % thousands(sum(c for _, _, c in affected)))
        print("      groesster Einzelwert hoechste Staffel: %.2f EUR"
              % max(a for a, _, _ in affected))

    print("\n    Wirkung auf die Spitze (Anteil der teuersten 1 %% an der Gesamtsumme):")
    for label, series in (("hoechste Staffel", highest), ("niedrigste Staffel", lowest),
                          ("Mindestkauf", floor)):
        ordered = sorted(series, reverse=True)
        cut = max(1, len(ordered) // 100)
        print("      %-20s %5.1f%%   Summe %s EUR"
              % (label, 100.0 * sum(ordered[:cut]) / sum(ordered), thousands(sum(ordered))))


def check_availability(count=2000, seed=20260815):
    """availableForSale wurde in der Sichtung nicht erfasst. Produkte mit
    availableForSale=false liefern auf der Website 404 — ein Affiliate-Link
    dorthin ist tot."""
    print("(e) Anteil nicht verkäuflicher Zeilen (availableForSale=false)\n")
    connection = db()
    handles = [row[0] for row in connection.execute(
        "SELECT handle FROM products ORDER BY handle").fetchall()]
    random.seed(seed)
    chosen = random.sample(handles, min(count, len(handles)))

    available = unavailable = missing = 0
    cross = {}
    for start in range(0, len(chosen), 250):
        chunk = chosen[start:start + 250]
        selection = "".join(
            'h%s:product(handle:"%s"){availableForSale totalInventory} ' % (h, h) for h in chunk)
        data = gql("{ %s }" % selection, retries=2, timeout=120)
        payload = (data.get("data") or {})
        for handle in chunk:
            node = payload.get("h" + handle)
            if not node:
                missing += 1
                continue
            sellable = bool(node.get("availableForSale"))
            stock = node.get("totalInventory")
            key = (sellable, (stock or 0) > 0)
            cross[key] = cross.get(key, 0) + 1
            if sellable:
                available += 1
            else:
                unavailable += 1
        time.sleep(0.05)

    checked = available + unavailable
    print("    Stichprobe %s, seed %d, nicht auffindbar %d" % (thousands(len(chosen)), seed, missing))
    print("    availableForSale=true   %8s  %5.1f%%" % (thousands(available), 100.0 * available / checked))
    print("    availableForSale=false  %8s  %5.1f%%" % (thousands(unavailable), 100.0 * unavailable / checked))
    print("\n    Kreuztabelle gegen totalInventory:")
    for (sellable, in_stock), n in sorted(cross.items(), key=lambda kv: -kv[1]):
        print("      verkäuflich=%-5s  Bestand>0=%-5s  %8s  %5.1f%%"
              % (sellable, in_stock, thousands(n), 100.0 * n / checked))
    print("\n    Hochrechnung auf 1.720.060 Zeilen: rund %s nicht verkäuflich (Schätzung"
          " aus der Stichprobe, 95%%-Intervall etwa +/-%.1f Punkte)."
          % (thousands(1720060 * unavailable / checked),
             196 * ((unavailable / checked) * (1 - unavailable / checked) / checked) ** 0.5))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "pages"
    if command == "pages":
        check_pages(int(sys.argv[2]) if len(sys.argv) > 2 else 50,
                    int(sys.argv[3]) if len(sys.argv) > 3 else 20260815)
    elif command == "context":
        check_context()
    elif command == "variants":
        check_variants(int(sys.argv[2]) if len(sys.argv) > 2 else 8)
    elif command == "basket":
        check_basket()
    elif command == "availability":
        check_availability(int(sys.argv[2]) if len(sys.argv) > 2 else 2000,
                           int(sys.argv[3]) if len(sys.argv) > 3 else 20260815)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
