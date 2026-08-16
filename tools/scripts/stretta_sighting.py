"""Vollsichtung des Stretta-Katalogs: eine Zeile je Produkt in einer eigenen
SQLite-Datei, plus Auswertung für die Umfangsentscheidung.

    python3 tools/scripts/stretta_sighting.py ids       # Phase 1: ID-Liste aus der Sitemap
    python3 tools/scripts/stretta_sighting.py run [n]    # Phase 2: Produkte holen, n Threads
    python3 tools/scripts/stretta_sighting.py report     # Auswertung

Schreibt nach storage/stretta-sighting.sqlite3 (gitignored). Die
Anwendungsdatenbank wird nur für den Komponistenabgleich und nur lesend
geöffnet.

Warum zwei Phasen statt eines Durchlaufs über products(first:250)?
Die Storefront-API begrenzt JEDE Connection auf 25.000 Elemente
("Platform limit for pagination (25000 items) exceeded"). Der Cursor trägt
den absoluten Offset, ein Wiederaufsetzen umgeht die Grenze also nicht.
1,87 Mio. Produkte sind über die Connection grundsätzlich nicht erreichbar.

Stattdessen liefert die Sitemap die vollständige ID-Liste, und die Produkte
werden über aliasierte product(handle:)-Batches geholt. Das kostet je Produkt
rund das Zwanzigfache an Query-Cost (1750 statt 89 pro 250 Produkte), ist
dafür aber abzählbar: zu jeder ID ist am Ende bekannt, ob sie geholt wurde
oder nicht existiert.
"""

import collections
import json
import os
import re
import sqlite3
import sys
import threading
import time
import urllib.error
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stretta_api import fetch, gql, metafield_identifiers  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB_PATH = os.path.join(ROOT, "storage", "stretta-sighting.sqlite3")
APP_DB_PATH = os.path.join(ROOT, "storage", "development.sqlite3")

SITEMAP_INDEX = "https://www.stretta-music.de/sitemap.xml"
SITEMAP_CHILD = "https://www.stretta-music.de/sitemap/articles/%d.xml"
BATCH = 250
WORKERS = 4
ATTEMPTS = 10
BYTES_PER_ROW = 4096  # gemessen an der bestehenden ScoreBase-DB
REPORT_EVERY = 40

OPEN, FETCHED, MISSING = 0, 1, 2

METAFIELDS = (
    ("custom", "texts"),
    ("custom", "minquantity"),
    ("custom", "bulk_prices"),
    ("custom", "pages"),
    ("custom", "difficulty"),
    ("custom", "order_no"),
    ("facts", "ismn"),
    ("facts", "isbn"),
    ("stretta", "slugs"),
)

NODE_FIELDS = """
  handle title vendor productType totalInventory createdAt updatedAt
  featuredImage { url }
  priceRange { minVariantPrice { amount currencyCode } }
  compareAtPriceRange { minVariantPrice { amount } }
  metafields(identifiers:[%s]) { namespace key value }
""" % metafield_identifiers(METAFIELDS)

COLUMNS = (
    "handle", "title", "vendor", "product_type", "total_inventory",
    "created_at", "updated_at", "price", "compare_at_price", "currency",
    "has_image", "has_texts", "text_title", "text_subtitle", "itemtype",
    "instrument", "languages", "authors", "minquantity", "bulk_prices",
    "pages", "difficulty", "order_no", "ismn", "isbn", "slug_de", "slug_en",
    "expected_basket",
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS products (
  handle TEXT PRIMARY KEY, title TEXT, vendor TEXT, product_type TEXT,
  total_inventory INTEGER, created_at TEXT, updated_at TEXT,
  price REAL, compare_at_price REAL, currency TEXT,
  has_image INTEGER, has_texts INTEGER,
  text_title TEXT, text_subtitle TEXT, itemtype TEXT, instrument TEXT,
  languages TEXT, authors TEXT,
  minquantity INTEGER, bulk_prices TEXT, pages TEXT, difficulty TEXT,
  order_no TEXT, ismn TEXT, isbn TEXT, slug_de TEXT, slug_en TEXT,
  expected_basket REAL
);
CREATE TABLE IF NOT EXISTS catalog_ids (handle TEXT PRIMARY KEY, state INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS catalog_ids_open ON catalog_ids(state);
CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT);
"""


def open_db():
    db = sqlite3.connect(DB_PATH, timeout=120)
    db.executescript(SCHEMA)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    return db


def get_state(db, key, default=None):
    row = db.execute("SELECT value FROM state WHERE key=?", (key,)).fetchone()
    return row[0] if row else default


def set_state(db, key, value):
    db.execute("INSERT OR REPLACE INTO state VALUES (?,?)", (key, str(value)))


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def thousands(value):
    return format(int(value), ",d").replace(",", ".")


def hms(seconds):
    seconds = int(seconds)
    return "%d:%02d:%02d" % (seconds // 3600, seconds % 3600 // 60, seconds % 60)


def expected_basket(price, minquantity, bulk_prices):
    if price is None:
        return None
    if bulk_prices:
        try:
            tiers = json.loads(bulk_prices)
        except ValueError:
            tiers = None
        if isinstance(tiers, list) and tiers:
            top = max(tiers, key=lambda tier: number(tier.get("amount")) or 0)
            amount, tier_price = number(top.get("amount")), number(top.get("price"))
            if amount and tier_price is not None:
                return amount * tier_price
    if minquantity and minquantity > 1:
        return price * minquantity
    return price


def to_row(node):
    fields = {}
    for field in node.get("metafields") or []:
        if field:
            fields["%s.%s" % (field["namespace"], field["key"])] = field.get("value")

    def parsed(raw):
        if not raw:
            return {}
        try:
            value = json.loads(raw)
        except ValueError:
            return {}
        return value if isinstance(value, dict) else {}

    raw_texts = fields.get("custom.texts")
    texts = parsed(raw_texts)
    slugs = parsed(fields.get("stretta.slugs"))

    price_range = (node.get("priceRange") or {}).get("minVariantPrice") or {}
    compare_range = (node.get("compareAtPriceRange") or {}).get("minVariantPrice") or {}
    price = number(price_range.get("amount"))
    minquantity = number(fields.get("custom.minquantity"))
    minquantity = int(minquantity) if minquantity else None
    bulk_prices = fields.get("custom.bulk_prices")
    authors = texts.get("authors")
    languages = texts.get("languages")

    return (
        node.get("handle"),
        node.get("title"),
        node.get("vendor"),
        node.get("productType"),
        node.get("totalInventory"),
        node.get("createdAt"),
        node.get("updatedAt"),
        price,
        number(compare_range.get("amount")),
        price_range.get("currencyCode"),
        1 if node.get("featuredImage") else 0,
        1 if raw_texts else 0,
        texts.get("title"),
        texts.get("subtitle"),
        texts.get("itemtype"),
        texts.get("instrument"),
        json.dumps(languages, ensure_ascii=False) if languages else None,
        json.dumps(authors, ensure_ascii=False) if authors else None,
        minquantity,
        bulk_prices,
        fields.get("custom.pages"),
        fields.get("custom.difficulty"),
        fields.get("custom.order_no"),
        fields.get("facts.ismn"),
        fields.get("facts.isbn"),
        slugs.get("DE"),
        slugs.get("EN"),
        expected_basket(price, minquantity, bulk_prices),
    )


# ------------------------------------------------------- Phase 1: ID-Liste

def collect_ids():
    db = open_db()
    index = fetch(SITEMAP_INDEX)
    files = sorted(int(m) for m in re.findall(r"/sitemap/articles/(\d+)\.xml", index))
    start = int(get_state(db, "sitemap_next", 0))
    print("articles-Kinddateien: %d, beginne bei %d" % (len(files), start))

    started = time.time()
    urls_total = int(get_state(db, "sitemap_urls", 0))
    unmatched = int(get_state(db, "sitemap_unmatched", 0))
    for position, number_ in enumerate(files):
        if number_ < start:
            continue
        for attempt in range(ATTEMPTS):
            try:
                xml = fetch(SITEMAP_CHILD % number_, timeout=90)
                break
            except Exception as error:
                if attempt == ATTEMPTS - 1:
                    raise
                print("  Datei %d: %s — neuer Versuch" % (number_, error), flush=True)
                time.sleep(min(60, 3 * 2 ** attempt))

        locs = len(re.findall(r"<loc>", xml))
        ids = re.findall(r"-nr-(\d+)\.html", xml)
        urls_total += locs
        unmatched += locs - len(ids)

        db.execute("BEGIN")
        db.executemany(
            "INSERT OR IGNORE INTO catalog_ids(handle) VALUES (?)", [(i,) for i in ids]
        )
        set_state(db, "sitemap_next", number_ + 1)
        set_state(db, "sitemap_urls", urls_total)
        set_state(db, "sitemap_unmatched", unmatched)
        db.commit()

        if position % 100 == 0 or number_ == files[-1]:
            known = db.execute("SELECT COUNT(*) FROM catalog_ids").fetchone()[0]
            print("  Datei %4d/%d  %s IDs bekannt  %s"
                  % (number_, files[-1], thousands(known), hms(time.time() - started)), flush=True)

    known = db.execute("SELECT COUNT(*) FROM catalog_ids").fetchone()[0]
    set_state(db, "ids_done", "1")
    db.commit()
    print("\nID-Liste vollständig: %s verschiedene IDs aus %s <loc>-Einträgen "
          "(%s Einträge ohne -nr-<ID>.html-Muster), %s"
          % (thousands(known), thousands(urls_total), thousands(unmatched), hms(time.time() - started)))


# ------------------------------------------------------ Phase 2: Produkte

_pace = {"value": 0.0}
_pace_lock = threading.Lock()


def slow_down():
    with _pace_lock:
        _pace["value"] = min(3.0, max(_pace["value"] * 2, 0.25))
        return _pace["value"]


def fetch_batch(handles):
    """Gibt (nodes, fehlende_handles) zurück. Jeder Fehler gilt als
    vorübergehend — INTERNAL_SERVER_ERROR tritt bei Shopify sporadisch auf."""
    selection = "".join(
        'h%s:product(handle:"%s"){%s} ' % (handle, handle, NODE_FIELDS) for handle in handles
    )
    query = "{ %s }" % selection
    last = None
    for attempt in range(ATTEMPTS):
        if attempt:
            wait = min(180, 4 * 2 ** attempt)
            print("  Batch-Versuch %d/%d nach %ds — %s" % (attempt + 1, ATTEMPTS, wait, last), flush=True)
            time.sleep(wait)
        if _pace["value"]:
            time.sleep(_pace["value"])
        try:
            data = gql(query, retries=1, timeout=180)
        except urllib.error.HTTPError as error:
            last = "HTTP %d" % error.code
            if error.code in (429, 430):
                slow_down()
            continue
        except Exception as error:
            last = "%s: %s" % (type(error).__name__, error)
            continue

        payload = data.get("data") or {}
        errors = data.get("errors")
        if errors:
            codes = {(e.get("extensions") or {}).get("code") for e in errors}
            if "THROTTLED" in codes:
                slow_down()
            last = json.dumps(errors)[:200]
            if not payload:
                continue

        nodes, missing = [], []
        for handle in handles:
            node = payload.get("h" + handle)
            if node and node.get("handle"):
                nodes.append(node)
            else:
                missing.append(handle)
        return nodes, missing
    print("  Batch endgültig aufgegeben (%d IDs bleiben offen): %s" % (len(handles), last), flush=True)
    return None, None


def run(workers=WORKERS):
    db = open_db()
    if not get_state(db, "ids_done"):
        sys.exit("Phase 1 fehlt oder ist unvollständig — erst 'ids' laufen lassen.")

    db.execute(
        "UPDATE catalog_ids SET state=? WHERE state=? AND handle IN (SELECT handle FROM products)",
        (FETCHED, OPEN),
    )
    db.commit()

    total = db.execute("SELECT COUNT(*) FROM catalog_ids").fetchone()[0]
    done_at_start = db.execute("SELECT COUNT(*) FROM catalog_ids WHERE state<>?", (OPEN,)).fetchone()[0]
    print("IDs gesamt %s, davon erledigt %s, offen %s — %d Threads"
          % (thousands(total), thousands(done_at_start), thousands(total - done_at_start), workers))

    insert = "INSERT OR REPLACE INTO products VALUES (%s)" % ",".join("?" * len(COLUMNS))
    started, done, found, missing_total, batches = time.time(), done_at_start, 0, 0, 0

    window = workers * 3  # begrenzt die gleichzeitig im Speicher gehaltenen Antworten
    with ThreadPoolExecutor(workers) as pool:
        while True:
            open_ids = [
                row[0] for row in db.execute(
                    "SELECT handle FROM catalog_ids WHERE state=? LIMIT 100000", (OPEN,)
                )
            ]
            if not open_ids:
                break
            chunks = [open_ids[i:i + BATCH] for i in range(0, len(open_ids), BATCH)]
            progressed = False
            for start in range(0, len(chunks), window):
                for nodes, missing in pool.map(fetch_batch, chunks[start:start + window]):
                    if nodes is None:
                        continue
                    progressed = True
                    db.execute("BEGIN")
                    if nodes:
                        db.executemany(insert, [to_row(node) for node in nodes])
                    db.executemany(
                        "UPDATE catalog_ids SET state=? WHERE handle=?",
                        [(FETCHED, node["handle"]) for node in nodes]
                        + [(MISSING, handle) for handle in missing],
                    )
                    db.commit()

                    done += len(nodes) + len(missing)
                    found += len(nodes)
                    missing_total += len(missing)
                    batches += 1
                    if batches % REPORT_EVERY == 0:
                        elapsed = time.time() - started
                        rate = (done - done_at_start) / elapsed if elapsed else 0
                        print("[%5.1f%%] %9s IDs  %9s Produkte  %8s tot  %s  Rest ~%s  %.0f/s"
                              % (100.0 * done / total, thousands(done), thousands(found),
                                 thousands(missing_total), hms(elapsed),
                                 hms((total - done) / rate if rate else 0), rate), flush=True)
            if not progressed:
                print("Kein Fortschritt mehr — %s IDs bleiben offen. Abbruch."
                      % thousands(len(open_ids)), flush=True)
                break

    stored = db.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    dead = db.execute("SELECT COUNT(*) FROM catalog_ids WHERE state=?", (MISSING,)).fetchone()[0]
    set_state(db, "run_done", "1")
    db.commit()
    print("\nFertig in %s. %s Zeilen gespeichert, %s IDs ohne Produkt."
          % (hms(time.time() - started), thousands(stored), thousands(dead)))


# ---------------------------------------------------------------- Auswertung

def bar(count, total, width=28):
    return "#" * int(round(width * count / total)) if total else ""


def enumeration(db, total):
    print("\n== 0. Abzählbarkeit der Sichtung ==\n")
    ids = db.execute("SELECT COUNT(*) FROM catalog_ids").fetchone()[0]
    dead = db.execute("SELECT COUNT(*) FROM catalog_ids WHERE state=?", (MISSING,)).fetchone()[0]
    still_open = db.execute("SELECT COUNT(*) FROM catalog_ids WHERE state=?", (OPEN,)).fetchone()[0]
    urls = get_state(db, "sitemap_urls", "?")
    unmatched = get_state(db, "sitemap_unmatched", "?")
    print("  <loc>-Einträge in der Sitemap        %12s" % urls)
    print("  davon ohne -nr-<ID>.html-Muster      %12s" % unmatched)
    print("  verschiedene IDs                     %12s" % thousands(ids))
    print("  davon Produkt geliefert              %12s  %5.1f%%" % (thousands(total), 100.0 * total / ids))
    print("  davon kein Produkt (Karteileiche)    %12s  %5.1f%%" % (thousands(dead), 100.0 * dead / ids))
    print("  noch offen                           %12s" % thousands(still_open))
    if still_open:
        print("  ACHTUNG: Sichtung unvollständig, alle folgenden Zahlen sind Teilmengen.")


def coverage(db, total):
    checks = (
        ("custom.texts vorhanden", "has_texts=1"),
        ("itemtype gefüllt", "itemtype IS NOT NULL AND TRIM(itemtype)<>''"),
        ("featuredImage", "has_image=1"),
        ("minquantity > 1", "minquantity>1"),
        ("bulk_prices Feld da", "bulk_prices IS NOT NULL"),
        ("bulk_prices befüllt", "bulk_prices IS NOT NULL AND bulk_prices NOT IN ('','[]')"),
        ("difficulty", "difficulty IS NOT NULL AND TRIM(difficulty)<>''"),
        ("facts.ismn", "ismn IS NOT NULL AND TRIM(ismn)<>''"),
        ("facts.isbn", "isbn IS NOT NULL AND TRIM(isbn)<>''"),
        ("slugs DE", "slug_de IS NOT NULL"),
        ("slugs EN", "slug_en IS NOT NULL"),
        ("order_no", "order_no IS NOT NULL AND TRIM(order_no)<>''"),
        ("pages", "pages IS NOT NULL"),
        ("Preis > 0", "price>0"),
        ("Streichpreis > 0", "compare_at_price>0"),
    )
    print("\n== 1. Feldabdeckung ==\n")
    for label, condition in checks:
        count = db.execute("SELECT COUNT(*) FROM products WHERE %s" % condition).fetchone()[0]
        print("  %-24s %9s  %5.1f%%  %s" % (label, thousands(count), 100.0 * count / total, bar(count, total)))


def authors_coverage(db, total):
    with_entries = with_role = with_slug = empty = 0
    for (raw,) in db.execute("SELECT authors FROM products"):
        entries = None
        if raw:
            try:
                entries = json.loads(raw)
            except ValueError:
                entries = None
        if not entries:
            empty += 1
            continue
        with_entries += 1
        authored = [e for e in entries if isinstance(e, dict) and e.get("role") == "author"]
        if authored:
            with_role += 1
            if any(e.get("slug") for e in authored):
                with_slug += 1
    print("\n  Autorenfelder:")
    for label, count in (
        ("authors nicht leer", with_entries),
        ("mit role=author", with_role),
        ("Autor mit slug", with_slug),
        ("ohne Autoren", empty),
    ):
        print("  %-24s %9s  %5.1f%%  %s" % (label, thousands(count), 100.0 * count / total, bar(count, total)))


def itemtypes(db, total, top=100):
    print("\n== 2. itemtype-Verteilung (Top %d) ==\n" % top)
    rows = db.execute(
        "SELECT COALESCE(NULLIF(TRIM(itemtype),''),'(leer)') AS t, COUNT(*) c "
        "FROM products GROUP BY t ORDER BY c DESC"
    ).fetchall()
    print("  verschiedene itemtype-Werte: %s\n" % thousands(len(rows)))
    cumulative = 0
    for rank, (name, count) in enumerate(rows[:top], 1):
        cumulative += count
        print("  %3d. %-46s %9s  %5.2f%%  kum %5.1f%%"
              % (rank, name[:46], thousands(count), 100.0 * count / total, 100.0 * cumulative / total))
    print("\n  Rest (%s weitere Werte): %s Zeilen, %.1f%%"
          % (thousands(max(0, len(rows) - top)), thousands(total - cumulative),
             100.0 * (total - cumulative) / total))


def baskets(db, total):
    print("\n== 3. expected_basket ==\n")
    for label, condition in (
        ("kein Preis", "expected_basket IS NULL OR expected_basket<=0"),
        ("< 10 EUR", "expected_basket>0 AND expected_basket<10"),
        ("10-30 EUR", "expected_basket>=10 AND expected_basket<30"),
        ("30-100 EUR", "expected_basket>=30 AND expected_basket<100"),
        (">= 100 EUR", "expected_basket>=100"),
    ):
        count = db.execute("SELECT COUNT(*) FROM products WHERE %s" % condition).fetchone()[0]
        print("  %-12s %9s  %5.1f%%  %s" % (label, thousands(count), 100.0 * count / total, bar(count, total)))

    print("\n  Welche Regel den Wert erzeugt hat:")
    for label, condition in (
        ("Staffelpreis", "bulk_prices IS NOT NULL AND bulk_prices NOT IN ('','[]')"),
        ("price x minquantity", "(bulk_prices IS NULL OR bulk_prices IN ('','[]')) AND minquantity>1"),
        ("price unverändert", "(bulk_prices IS NULL OR bulk_prices IN ('','[]')) AND (minquantity IS NULL OR minquantity<=1)"),
    ):
        count, value = db.execute(
            "SELECT COUNT(*), COALESCE(SUM(expected_basket),0) FROM products WHERE %s" % condition
        ).fetchone()
        print("    %-20s %9s Zeilen  %5.1f%%   Korbsumme %16s EUR"
              % (label, thousands(count), 100.0 * count / total, thousands(value)))

    grand = db.execute("SELECT COALESCE(SUM(expected_basket),0) FROM products").fetchone()[0]
    priced = db.execute("SELECT COUNT(*) FROM products WHERE expected_basket>0").fetchone()[0]
    print("\n  Summe aller expected_basket: %s EUR   Mittelwert %.2f EUR"
          % (thousands(grand), grand / priced if priced else 0))
    print("\n  Anteil der teuersten ... am Gesamtwarenkorbwert:")
    for share in (1, 5, 10, 25):
        limit = max(1, int(total * share / 100))
        top_sum = db.execute(
            "SELECT COALESCE(SUM(expected_basket),0) FROM "
            "(SELECT expected_basket FROM products ORDER BY expected_basket DESC LIMIT ?)", (limit,)
        ).fetchone()[0]
        print("    obere %2d%% (%10s Zeilen)  %6.1f%%"
              % (share, thousands(limit), 100.0 * top_sum / grand if grand else 0))

    plain = db.execute("SELECT COALESCE(SUM(price),0) FROM products").fetchone()[0]
    print("\n  Ohne Mindestmengen-/Staffelaufschlag (nur price): %s EUR — expected_basket ist das %.2f-fache"
          % (thousands(plain), grand / plain if plain else 0))


def vendors(db, total, top=30):
    print("\n== 4. Verlagsverteilung ==\n")
    distinct = db.execute(
        "SELECT COUNT(DISTINCT COALESCE(NULLIF(TRIM(vendor),''),'(leer)')) FROM products"
    ).fetchone()[0]
    print("  verschiedene Verlage: %s\n" % thousands(distinct))
    cumulative = 0
    for rank, (name, count, basket) in enumerate(db.execute(
        "SELECT COALESCE(NULLIF(TRIM(vendor),''),'(leer)') AS v, COUNT(*) c, "
        "COALESCE(SUM(expected_basket),0) s FROM products GROUP BY v ORDER BY c DESC LIMIT ?", (top,)
    ), 1):
        cumulative += count
        print("  %3d. %-38s %9s  %5.2f%%  kum %5.1f%%   Korb %12s EUR"
              % (rank, name[:38], thousands(count), 100.0 * count / total,
                 100.0 * cumulative / total, thousands(basket)))


def thresholds(db, total):
    print("\n== 5. Schwellwerttabelle (expected_basket) ==\n")
    print("  %-34s %11s %8s %13s" % ("Schwelle", "Zeilen", "Anteil", "Platz @4,0KB"))
    for extra, label_suffix in ((None, ""), ("itemtype IS NOT NULL AND TRIM(itemtype)<>''", " + itemtype")):
        for threshold in (0, 5, 10, 20, 50, 100):
            condition = "expected_basket >= %d" % threshold
            if extra:
                condition += " AND " + extra
            count = db.execute("SELECT COUNT(*) FROM products WHERE %s" % condition).fetchone()[0]
            label = ("alle Zeilen" if threshold == 0 else ">= %d EUR" % threshold) + label_suffix
            print("  %-34s %11s %7.1f%% %10.2f GB"
                  % (label, thousands(count), 100.0 * count / total, count * BYTES_PER_ROW / 1024 ** 3))
        print()


def fold(name):
    return " ".join(name.split()).casefold()


def swap_order(name):
    parts = name.split()
    if "," in name or len(parts) < 2 or len(parts) > 4:
        return None
    return "%s, %s" % (parts[-1], " ".join(parts[:-1]))


def composers(db, total):
    print("\n== 6. Komponistenabgleich gegen composer_mappings ==\n")
    if not os.path.exists(APP_DB_PATH):
        print("  storage/development.sqlite3 nicht gefunden — Abgleich übersprungen.")
        return

    app = sqlite3.connect("file:%s?mode=ro" % APP_DB_PATH, uri=True)
    originals, both = set(), set()
    for original, normalized in app.execute(
        "SELECT original_name, normalized_name FROM composer_mappings"
    ):
        if original:
            originals.add(original)
            both.add(original)
        if normalized:
            both.add(normalized)
    app.close()
    folded = {fold(name) for name in both}
    print("  composer_mappings: %s Zeilen, %s verschiedene Namen (beide Spalten)"
          % (thousands(len(originals)), thousands(len(both))))

    with_author = exact = either = loose = swapped = 0
    names_seen = collections.Counter()
    for (raw,) in db.execute("SELECT authors FROM products WHERE authors IS NOT NULL"):
        try:
            entries = json.loads(raw)
        except ValueError:
            continue
        names = [
            entry["name"].strip() for entry in entries
            if isinstance(entry, dict) and entry.get("role") == "author" and entry.get("name")
        ]
        if not names:
            continue
        with_author += 1
        for name in names:
            names_seen[name] += 1
        if any(name in originals for name in names):
            exact += 1
        if any(name in both for name in names):
            either += 1
        elif any(fold(name) in folded for name in names):
            loose += 1
        elif any(fold(swap_order(name)) in folded for name in names if swap_order(name)):
            swapped += 1

    print("  Produkte mit role=author:   %s  (%.1f%% aller Zeilen)"
          % (thousands(with_author), 100.0 * with_author / total))
    print("  verschiedene Komponistennamen bei Stretta: %s\n" % thousands(len(names_seen)))
    if not with_author:
        return
    print("  Treffer, gemessen an den %s Zeilen mit Komponist:" % thousands(with_author))
    for label, count in (
        ("exakt in original_name (= ComposerMapping.lookup)", exact),
        ("exakt in original_name ODER normalized_name", either),
        ("zusätzlich nur nach Groß/Klein+Leerraum", loose),
        ("zusätzlich erst nach Namensumkehr", swapped),
    ):
        print("    %-52s %10s  %5.1f%%" % (label, thousands(count), 100.0 * count / with_author))
    hits = either + loose + swapped
    print("    %-52s %10s  %5.1f%%  (%.1f%% aller Zeilen)"
          % ("Obergrenze (alle Varianten)", thousands(hits),
             100.0 * hits / with_author, 100.0 * hits / total))

    print("\n  Häufigste Stretta-Komponisten und ob bekannt:")
    for name, count in names_seen.most_common(30):
        mark = "ja " if name in both else ("fold" if fold(name) in folded else "NEIN")
        print("    %-4s %-44s %9s" % (mark, name[:44], thousands(count)))


def extras(db, total):
    print("\n== Zusatzbeobachtungen ==\n")
    print("  productType:")
    for name, count in db.execute(
        "SELECT COALESCE(NULLIF(TRIM(product_type),''),'(leer)') t, COUNT(*) c "
        "FROM products GROUP BY t ORDER BY c DESC LIMIT 15"
    ):
        print("    %-24s %9s  %5.1f%%" % (name, thousands(count), 100.0 * count / total))

    print("\n  Währungen:")
    for name, count in db.execute(
        "SELECT COALESCE(currency,'(leer)'), COUNT(*) FROM products GROUP BY 1 ORDER BY 2 DESC LIMIT 5"
    ):
        print("    %-8s %s" % (name, thousands(count)))

    print("\n  difficulty-Verteilung:")
    for name, count in db.execute(
        "SELECT COALESCE(NULLIF(TRIM(difficulty),''),'(leer)') d, COUNT(*) c "
        "FROM products GROUP BY d ORDER BY c DESC LIMIT 10"
    ):
        print("    %-10s %9s  %5.1f%%" % (name, thousands(count), 100.0 * count / total))

    print("\n  Verfügbarkeit und Alter:")
    for label, condition in (
        ("totalInventory > 0", "total_inventory>0"),
        ("totalInventory = 0", "total_inventory=0"),
        ("totalInventory NULL", "total_inventory IS NULL"),
        ("createdAt 2026", "created_at LIKE '2026%'"),
        ("updatedAt 2026", "updated_at LIKE '2026%'"),
        ("Preis fehlt oder 0", "price IS NULL OR price=0"),
    ):
        count = db.execute("SELECT COUNT(*) FROM products WHERE %s" % condition).fetchone()[0]
        print("    %-22s %9s  %5.1f%%" % (label, thousands(count), 100.0 * count / total))

    print("\n  updatedAt nach Monat (Top 8) — entscheidet, ob ein Delta-Sync billig ist:")
    for month, count in db.execute(
        "SELECT substr(updated_at,1,7) m, COUNT(*) c FROM products GROUP BY m ORDER BY c DESC LIMIT 8"
    ):
        print("    %-10s %9s  %5.1f%%" % (month, thousands(count), 100.0 * count / total))

    print("\n  createdAt nach Jahr:")
    for year, count in db.execute(
        "SELECT substr(created_at,1,4) y, COUNT(*) c FROM products GROUP BY y ORDER BY y"
    ):
        print("    %-10s %9s  %5.1f%%" % (year, thousands(count), 100.0 * count / total))

    groups, rows_in_groups = db.execute(
        "SELECT COUNT(*), COALESCE(SUM(c),0) FROM "
        "(SELECT COUNT(*) c FROM products WHERE text_title IS NOT NULL "
        " GROUP BY text_title, COALESCE(authors,'') HAVING c>1)"
    ).fetchone()
    print("\n  Werkgruppen (custom.texts.title + Autoren identisch):")
    print("    %s Gruppen umfassen %s Zeilen (%.1f%%)"
          % (thousands(groups), thousands(rows_in_groups), 100.0 * rows_in_groups / total))


def report():
    if not os.path.exists(DB_PATH):
        sys.exit("Sichtungsdatei fehlt: %s" % DB_PATH)
    db = open_db()
    total = db.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    if not total:
        sys.exit("Sichtungsdatei ist leer.")
    print("Sichtung: %s" % DB_PATH)
    print("  Produktzeilen: %s   Datei: %.2f GB   Lauf %s"
          % (thousands(total), os.path.getsize(DB_PATH) / 1024.0 ** 3,
             "abgeschlossen" if get_state(db, "run_done") else "UNVOLLSTÄNDIG"))

    enumeration(db, total)
    coverage(db, total)
    authors_coverage(db, total)
    itemtypes(db, total)
    baskets(db, total)
    vendors(db, total)
    thresholds(db, total)
    composers(db, total)
    extras(db, total)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "run"
    if command == "ids":
        collect_ids()
    elif command == "run":
        run(int(sys.argv[2]) if len(sys.argv) > 2 else WORKERS)
    elif command == "report":
        report()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
