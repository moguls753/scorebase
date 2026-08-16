"""Erhebt zwei fehlende Felder über die bereits gesichteten Handles nach:
availableForSale und ob eine Vorschau-PDF existiert.

    python3 tools/scripts/stretta_backfill.py run [threads]
    python3 tools/scripts/stretta_backfill.py report

Beides sind harte Importfilter nach docs/stretta-import-plan.md §1. Schreibt
zwei neue Spalten in storage/stretta-sighting.sqlite3; die App-Datenbank wird
nicht angefasst.

Wiederaufsetzbar ohne eigenen Cursor: offen ist, was NULL ist. Ein Abbruch
kostet höchstens die gerade laufenden Stapel.

Das Metafeld liegt im Namespace `preview`, nicht `custom` — `custom.pdfs`
liefert null. Gespeichert wird nur, ob die Liste nicht leer ist.
"""

import json
import os
import sys
import time
import urllib.error
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stretta_api import gql  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB_PATH = os.path.join(ROOT, "storage", "stretta-sighting.sqlite3")

BATCH = 250
WORKERS = 5
ATTEMPTS = 10
REPORT_EVERY = 40

import sqlite3  # noqa: E402


def open_db():
    db = sqlite3.connect(DB_PATH, timeout=120)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    return db


def ensure_columns(db):
    existing = {row[1] for row in db.execute("PRAGMA table_info(products)")}
    for column in ("available_for_sale", "has_preview_pdf"):
        if column not in existing:
            db.execute("ALTER TABLE products ADD COLUMN %s INTEGER" % column)
            print("Spalte angelegt: %s" % column)
    db.execute("CREATE INDEX IF NOT EXISTS ix_products_afs_open "
               "ON products(available_for_sale) WHERE available_for_sale IS NULL")
    db.commit()


def thousands(value):
    return format(int(value), ",d").replace(",", ".")


def hms(seconds):
    seconds = int(seconds)
    return "%d:%02d:%02d" % (seconds // 3600, seconds % 3600 // 60, seconds % 60)


def fetch_batch(handles):
    selection = "".join(
        'h%s:product(handle:"%s"){availableForSale '
        'metafield(namespace:"preview",key:"pdfs"){value}} ' % (handle, handle)
        for handle in handles
    )
    query = "{ %s }" % selection
    last = None
    for attempt in range(ATTEMPTS):
        if attempt:
            wait = min(180, 4 * 2 ** attempt)
            print("  Versuch %d/%d nach %ds — %s" % (attempt + 1, ATTEMPTS, wait, last), flush=True)
            time.sleep(wait)
        try:
            data = gql(query, retries=1, timeout=180)
        except urllib.error.HTTPError as error:
            last = "HTTP %d" % error.code
            continue
        except Exception as error:
            last = "%s: %s" % (type(error).__name__, error)
            continue

        payload = data.get("data") or {}
        if data.get("errors") and not payload:
            last = json.dumps(data["errors"])[:200]
            continue
        if not payload:
            last = "leere Antwort"
            continue

        rows = []
        for handle in handles:
            node = payload.get("h" + handle)
            if node is None:
                # Produkt inzwischen weg: als nicht verkäuflich, ohne PDF führen.
                rows.append((0, 0, handle))
                continue
            field = node.get("metafield")
            raw = field.get("value") if field else None
            has_pdf = 0
            if raw:
                try:
                    parsed = json.loads(raw)
                    has_pdf = 1 if isinstance(parsed, list) and parsed else 0
                except ValueError:
                    has_pdf = 0
            rows.append((1 if node.get("availableForSale") else 0, has_pdf, handle))
        return rows
    print("  Stapel endgültig aufgegeben (%d Handles bleiben offen): %s"
          % (len(handles), last), flush=True)
    return None


def run(workers=WORKERS):
    db = open_db()
    ensure_columns(db)

    total = db.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    done_at_start = db.execute(
        "SELECT COUNT(*) FROM products WHERE available_for_sale IS NOT NULL").fetchone()[0]
    print("Zeilen %s, davon erledigt %s, offen %s — %d Threads"
          % (thousands(total), thousands(done_at_start), thousands(total - done_at_start), workers))

    started, done, batches = time.time(), done_at_start, 0
    window = workers * 3
    with ThreadPoolExecutor(workers) as pool:
        while True:
            open_ids = [row[0] for row in db.execute(
                "SELECT handle FROM products WHERE available_for_sale IS NULL LIMIT 100000")]
            if not open_ids:
                break
            chunks = [open_ids[i:i + BATCH] for i in range(0, len(open_ids), BATCH)]
            progressed = False
            for start in range(0, len(chunks), window):
                for rows in pool.map(fetch_batch, chunks[start:start + window]):
                    if rows is None:
                        continue
                    progressed = True
                    db.execute("BEGIN")
                    db.executemany(
                        "UPDATE products SET available_for_sale=?, has_preview_pdf=? "
                        "WHERE handle=?", rows)
                    db.commit()
                    done += len(rows)
                    batches += 1
                    if batches % REPORT_EVERY == 0:
                        elapsed = time.time() - started
                        rate = (done - done_at_start) / elapsed if elapsed else 0
                        print("[%5.1f%%] %9s Zeilen  %s  Rest ~%s  %.0f/s"
                              % (100.0 * done / total, thousands(done), hms(elapsed),
                                 hms((total - done) / rate if rate else 0), rate), flush=True)
            if not progressed:
                print("Kein Fortschritt mehr — %s Zeilen bleiben offen."
                      % thousands(len(open_ids)), flush=True)
                break

    print("\nFertig in %s." % hms(time.time() - started))
    report()


def report():
    db = open_db()
    total = db.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    filled = db.execute(
        "SELECT COUNT(*) FROM products WHERE available_for_sale IS NOT NULL").fetchone()[0]
    print("\n== Nacherhebung ==\n")
    print("  Zeilen gesamt          %12s" % thousands(total))
    print("  erhoben                %12s  %5.1f%%" % (thousands(filled), 100.0 * filled / total))
    if filled < total:
        print("  NOCH OFFEN             %12s" % thousands(total - filled))

    for label, condition in (
        ("availableForSale = true", "available_for_sale=1"),
        ("availableForSale = false", "available_for_sale=0"),
        ("Vorschau-PDF vorhanden", "has_preview_pdf=1"),
        ("verkäuflich UND Vorschau", "available_for_sale=1 AND has_preview_pdf=1"),
    ):
        count = db.execute("SELECT COUNT(*) FROM products WHERE %s" % condition).fetchone()[0]
        print("  %-22s %12s  %5.1f%%" % (label, thousands(count), 100.0 * count / total))

    print("\n  Kreuztabelle availableForSale x totalInventory:")
    for sellable, stock, count in db.execute(
        "SELECT available_for_sale, CASE WHEN total_inventory>0 THEN 'Bestand>0' ELSE 'Bestand=0' END, "
        "COUNT(*) FROM products GROUP BY 1,2 ORDER BY 3 DESC"
    ):
        print("    verkäuflich=%-4s %-10s %12s  %5.1f%%"
              % (sellable, stock, thousands(count), 100.0 * count / total))

    print("\n  Nicht verkäufliche Zeilen nach Verlag (Top 15):")
    for vendor, count, share in db.execute(
        "SELECT COALESCE(NULLIF(TRIM(vendor),''),'(leer)') v, "
        "SUM(CASE WHEN available_for_sale=0 THEN 1 ELSE 0 END) n, "
        "100.0*SUM(CASE WHEN available_for_sale=0 THEN 1 ELSE 0 END)/COUNT(*) "
        "FROM products GROUP BY v HAVING n>0 ORDER BY n DESC LIMIT 15"
    ):
        print("    %-34s %10s  %5.1f%% des Verlags" % (vendor[:34], thousands(count), share))

    print("\n  Verlorener Warenkorbwert (nicht verkäuflich, Spec-Formel):")
    lost, kept = db.execute("""
        SELECT SUM(CASE WHEN available_for_sale=0 THEN b ELSE 0 END),
               SUM(CASE WHEN available_for_sale=1 THEN b ELSE 0 END)
        FROM (SELECT available_for_sale,
                     COALESCE((SELECT MIN(json_extract(j.value,'$.amount')*json_extract(j.value,'$.price'))
                               FROM json_each(bulk_prices) j),
                              price*MAX(COALESCE(minquantity,1),1)) b
              FROM products)""").fetchone()
    print("    entfällt  %14s EUR" % thousands(lost or 0))
    print("    verbleibt %14s EUR" % thousands(kept or 0))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "run"
    if command == "run":
        run(int(sys.argv[2]) if len(sys.argv) > 2 else WORKERS)
    elif command == "report":
        report()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
