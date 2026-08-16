"""Leitet die itemtype-Listen ab und rechnet die Importkaskade aus
docs/stretta-import-plan.md §1.

    python3 tools/scripts/stretta_filter.py lists     # Top 1000 auszählen, Listen schreiben
    python3 tools/scripts/stretta_filter.py rest      # Restmenge und Ersatzregel
    python3 tools/scripts/stretta_filter.py cascade   # die drei Filter nacheinander
    python3 tools/scripts/stretta_filter.py sample [n] [seed]   # geschichtete Stichprobe
    python3 tools/scripts/stretta_filter.py buch [n]  # was die Buch-Regel hereinholt

Die Listen enthalten EXAKTE Werte, keine Präfixe: "Buch" darf "Notenbuch" und
"Lehrbuch (mit Noten)" nicht mitfangen. Materialisiert nach
tools/stretta-itemtype-lists.json, damit die Auswahl auditierbar ist und sich
nicht still mitverschiebt, wenn der Katalog wächst.

Eine Wertschwelle gibt es nicht mehr — der Server hat 44 GB frei.
"""

import json
import os
import random
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIGHTING_DB = os.path.join(ROOT, "storage", "stretta-sighting.sqlite3")
MATCH_DB = os.path.join(ROOT, "storage", "stretta-match.sqlite3")
LISTS_PATH = os.path.join(ROOT, "tools", "stretta-itemtype-lists.json")

TOP_N = 1000
BYTES_PER_ROW = 4096

# Kein Notenmaterial. Das Etikett der Quelle entscheidet: "Playback-CD (ohne
# Noten)" sagt es selbst, "Buch, CD" führt das Buch als Hauptartikel.
DENY = [
    # Bücher und Buchbindungen
    "Buch", "Buch (Gebunden)", "Buch (Kartoniert)", "Buch (Hardcover)",
    "Buch (Softcover)", "Buch (Klappenbroschur)", "Buch (Geheftet)",
    "Buch (kritischer Bericht, Hardcover)", "Buch (kritischer Bericht)",
    "Buch (Karte)", "Buch (Lexikon)", "Buch (Lexikon, Hardcover)", "Buch (Pappe)",
    "Buch (Leinen)", "Buch (Halbleinen)", "Buch (Faksimile)", "Buch (mit online Audio)",
    "Taschenbuch", "Taschenbuch (Kartoniert)", "Taschenbuch (Klappenbroschur)",
    "Bücher-Set", "2 Bücher", "2 Bücher (Hardcover)", "Bilderbuch",
    # Buch plus Beilage — Hauptartikel bleibt das Buch
    "Buch, CD", "Buch + CD", "Buch, DVD", "Buch, CD-Rom", "Buch, CD, DVD",
    "Buch + DVD", "Buch + CD + DVD", "Buch + DVD-ROM", "Buch + Online-Audio",
    "Buch + Medien Online", "Buch und MC", "Buch und Instrument",
    "Buch (Hardcover), CD", "Buch (Softcover), CD", "Buch, Playback-CD",
    "Buch (Lehrerband), CD", "Bilderbuch, CD",
    # Tonträger und Video
    "CD", "Audio-CD", "CD-Rom", "CD-Pack", "2 CDs (ohne Noten)", "2 Audio-CDs",
    "3 CDs", "4 CDs", "Playback-CD", "Playback-CD (ohne Noten)",
    "2 Playback-CDs (ohne Noten)", "3 Playback-CDs",
    "Playback-CD (mp3) (Chorstimme Sopran)", "Playback-CD (mp3) (Chorstimme Alt)",
    "Playback-CD (mp3) (Chorstimme Tenor)", "Playback-CD (mp3) (Chorstimme Bass)",
    "DVD (Lernvideo)", "2 DVDs (Lernvideo)", "DVD-Pack", "DVD, Booklet (Lehrmaterial)",
    "Video", "Video (Band)", "MP3-files (ohne Noten)", "Download (Audio)",
    "Musikkasette", "Diskette", "MIDI-Datei",
    # Text ohne Notentext
    "Textbuch", "Textheft", "Text", "Lehrerheft", "Lehrerhandbuch",
    "Lehrerhandbuch, Playback-CD", "Lösungsheft",
    "Songbook (mit Text und Akkorden – ohne Noten)",
    "Songbook (mit Text, Akkorden und Gitarrengriffen – ohne Noten)",
    "Songbook (mit Gitarren Tabs – ohne Noten)",
    # Lehrbuch ohne Notenzusage plus Beilage
    "Lehrbuch, CD", "Lehrbuch, DVD", "Lehrbuch (Arbeitsheft), Audio-CD",
    # Blankomaterial, Mappen, Zubehör, Merchandise
    "Notenpapier", "Notenschreibheft", "Notenblock", "Notenmappe",
    "Marschnotenmappe", "Chormappe", "Instrumentenkarte",
    "Poster", "Postkarte", "Postkarten (10 Stück)", "Postkarten (12 Stück)",
    "Kalender", "Bleistift", "Stifte-Etui (Federmäppchen)", "Schreibwaren",
    "Notizbuch", "Notizblock", "Tasse", "Tasche", "Tragetasche", "T-Shirt",
    "Socken", "Magnet", "Aufkleber", "Anstecknadel", "Schlüsselanhänger",
    "Christbaumschmuck", "Krawatte", "WEISS", "(blau)",
    "Zubehör", "Musikinstrument", "Musikinstrument, Tasche, Plektren",
    "Mikrofonstativ", "Boxenstativ", "Keyboardständer",
    "Spieluhr", "Klangspielzeug (für Kinder)", "Kartenspiel", "Musikspiel",
    "GAME-TOY", "Zeitschrift",
    # vom Auftrag ausdrücklich ergänzt
]

# Nicht sicher entscheidbar. Nach §1 ("Was nicht sicher als Noten erkannt ist,
# wird nicht importiert") fallen sie heraus, aber getrennt ausgewiesen.
UNCLEAR = [
    "Lehrbuch", "Schülerheft", "Arbeitsheft (Lehrmaterial)",
    "Schule", "Lehrmaterial", "Grifftabelle", "OTHER", "Spielbuch",
]

# Keine Wertliste, sondern eine Bedingung: blankes "Buch" mit gesetzter
# Besetzung ist fast immer falsch etikettiertes Notenmaterial (73 % der 59.720
# Zeilen tragen eine Besetzung; die Klammerformen "Buch (Gebunden)" und
# "Buch (Kartoniert)" dagegen 0 %). Ausnahme: instrument = "Libretto".
# SQL und Ruby werden mitgeschrieben, damit Skript und spätere Implementierung
# nicht auseinanderlaufen.
BUCH_RULE = {
    "name": "buch_mit_besetzung",
    "wirkung": "hebt DENY für exakt diesen Fall auf",
    "bedingung": {
        "itemtype_gleich": "Buch",
        "instrument_nicht_leer": True,
        "instrument_nicht_regex": "(?i)libretto",
    },
    "sql": ("TRIM(itemtype)='Buch' AND instrument IS NOT NULL AND TRIM(instrument)<>'' "
            "AND lower(instrument) NOT LIKE '%libretto%'"),
    "ruby": ("itemtype == 'Buch' && instrument.present? && "
             "!instrument.match?(/libretto/i)"),
}

EMPTY = "(leer)"


def is_noten(itemtype, instrument, allow, deny, unclear):
    """Einzige Wahrheit für 'gilt als Noten' nach itemtype-Regeln."""
    key = (itemtype or "").strip()
    if key == "Buch":
        text = (instrument or "").strip()
        return bool(text) and "libretto" not in text.lower()
    if key in allow:
        return True
    return False


def verdict_for(itemtype, instrument, pages, has_pdf, allow, deny, unclear):
    """Filterentscheidung samt Grund. Reihenfolge wie im JSON hinterlegt."""
    key = (itemtype or "").strip()
    if key == "Buch":
        text = (instrument or "").strip()
        if text and "libretto" not in text.lower():
            return "JA", "buchregel"
        return "NEIN", "deny"
    if key in allow:
        return "JA", "allow"
    if key in deny:
        return "NEIN", "deny"
    if key in unclear:
        return "NEIN", "unklar"
    if key:
        return "NEIN", "rest"
    if (instrument or "").strip() and (pages is not None or has_pdf == 1):
        return "JA", "ersatz+"
    return "NEIN", "ersatz-"


def noten_sql(lists):
    """(SQL-Fragment, Argumente) für dieselbe Regel, Tabellenalias p."""
    allow_sql, args = in_clause(lists["allow"])
    buch = ("TRIM(p.itemtype)='Buch' AND p.instrument IS NOT NULL "
            "AND TRIM(p.instrument)<>'' AND lower(p.instrument) NOT LIKE '%libretto%'")
    return "(TRIM(p.itemtype) IN %s OR (%s))" % (allow_sql, buch), args


def thousands(value):
    return format(int(value), ",d").replace(",", ".")


def sighting(writable=False):
    if writable:
        return sqlite3.connect(SIGHTING_DB, timeout=120)
    return sqlite3.connect("file:%s?mode=ro" % SIGHTING_DB, uri=True)


def top_itemtypes(db, limit=TOP_N):
    return db.execute(
        "SELECT COALESCE(NULLIF(TRIM(itemtype),''),?) v, COUNT(*) c "
        "FROM products GROUP BY v ORDER BY c DESC, v LIMIT ?", (EMPTY, limit)
    ).fetchall()


def load_lists():
    with open(LISTS_PATH) as handle:
        return json.load(handle)


def build_lists():
    db = sighting()
    rows = top_itemtypes(db)
    total = db.execute("SELECT COUNT(*) FROM products").fetchone()[0]

    print("Top %d itemtype-Werte (von %s verschiedenen)\n"
          % (TOP_N, thousands(db.execute(
              "SELECT COUNT(DISTINCT COALESCE(NULLIF(TRIM(itemtype),''),?)) FROM products",
              (EMPTY,)).fetchone()[0])))
    print("  %4s %-52s %9s %8s %8s  %s" % ("#", "itemtype", "Zeilen", "Anteil", "kum.", "Liste"))
    deny, unclear = set(DENY), set(UNCLEAR)
    allow, cumulative = [], 0
    for rank, (value, count) in enumerate(rows, 1):
        cumulative += count
        if value == EMPTY:
            bucket = "Ersatzregel"
        elif value == "Buch":
            bucket = "DENY, ausser mit Besetzung"
        elif value in deny:
            bucket = "DENY"
        elif value in unclear:
            bucket = "unklar"
        else:
            bucket = "ALLOW"
            allow.append(value)
        print("  %4d %-52s %9s %7.3f%% %7.2f%%  %s"
              % (rank, value[:52], thousands(count), 100.0 * count / total,
                 100.0 * cumulative / total, bucket))

    payload = {
        "erzeugt_aus": "storage/stretta-sighting.sqlite3, Top %d nach Zeilenzahl" % TOP_N,
        "regel": "exakte Werte, keine Praefixe; conditional_allow sticht deny",
        "reihenfolge": ["conditional_allow", "allow", "deny", "unclear", "rest"],
        "allow": sorted(allow),
        "deny": sorted(deny),
        "unclear": sorted(unclear),
        "conditional_allow": [BUCH_RULE],
    }
    with open(LISTS_PATH, "w") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=1)
    print("\ngeschrieben: %s  (allow %d, deny %d, unklar %d)"
          % (LISTS_PATH, len(allow), len(deny), len(unclear)))


def in_clause(values):
    return "(%s)" % ",".join("?" * len(values)), list(values)


def rest_analysis():
    lists = load_lists()
    db = sighting()
    total = db.execute("SELECT COUNT(*) FROM products").fetchone()[0]

    allow_sql, allow_args = in_clause(lists["allow"])
    deny_sql, deny_args = in_clause(lists["deny"])
    unclear_sql, unclear_args = in_clause(lists["unclear"])

    noten_frag, noten_args = noten_sql(lists)
    allow_n = db.execute(
        "SELECT COUNT(*) FROM products p WHERE %s" % noten_frag, noten_args
    ).fetchone()[0]
    buch_n = db.execute(
        "SELECT COUNT(*) FROM products p WHERE %s" % lists["conditional_allow"][0]["sql"]
    ).fetchone()[0]
    deny_n = db.execute(
        "SELECT COUNT(*) FROM products WHERE TRIM(itemtype) IN %s" % deny_sql, deny_args
    ).fetchone()[0] - buch_n
    unclear_n = db.execute(
        "SELECT COUNT(*) FROM products WHERE TRIM(itemtype) IN %s" % unclear_sql, unclear_args
    ).fetchone()[0]
    empty_n = db.execute(
        "SELECT COUNT(*) FROM products WHERE itemtype IS NULL OR TRIM(itemtype)=''"
    ).fetchone()[0]
    rest_n = total - allow_n - deny_n - unclear_n - empty_n

    print("== Wirkung der Listen ==\n")
    for label, count in (("Noten (Allowlist + Buch-Regel)", allow_n),
                         ("  davon über die Buch-Regel", buch_n),
                         ("DENY (keine Noten)", deny_n),
                         ("unklar (Top %d)" % TOP_N, unclear_n),
                         ("leerer itemtype", empty_n),
                         ("Restmenge (jenseits Top %d)" % TOP_N, rest_n)):
        print("  %-32s %10s  %5.1f%%" % (label, thousands(count), 100.0 * count / total))

    print("\n== Restmenge nach Verlag (Top 20) ==\n")
    print("  %-34s %10s %9s" % ("Verlag", "Restzeilen", "%d.Verl."))
    for vendor, count, share in db.execute("""
        SELECT COALESCE(NULLIF(TRIM(vendor),''),'(leer)') v, COUNT(*) n,
               100.0*COUNT(*)/(SELECT COUNT(*) FROM products p2 WHERE
                 COALESCE(NULLIF(TRIM(p2.vendor),''),'(leer)')=COALESCE(NULLIF(TRIM(products.vendor),''),'(leer)'))
        FROM products
        WHERE itemtype IS NOT NULL AND TRIM(itemtype)<>''
          AND TRIM(itemtype) NOT IN %s AND TRIM(itemtype) NOT IN %s AND TRIM(itemtype) NOT IN %s
        GROUP BY v ORDER BY n DESC LIMIT 20""" % (allow_sql, deny_sql, unclear_sql),
            allow_args + deny_args + unclear_args):
        print("  %-34s %10s %8.1f%%" % (vendor[:34], thousands(count), share))

    print("\n  Häufigste Werte in der Restmenge:")
    for value, count in db.execute("""
        SELECT TRIM(itemtype) v, COUNT(*) c FROM products
        WHERE itemtype IS NOT NULL AND TRIM(itemtype)<>''
          AND TRIM(itemtype) NOT IN %s AND TRIM(itemtype) NOT IN %s AND TRIM(itemtype) NOT IN %s
        GROUP BY v ORDER BY c DESC LIMIT 20""" % (allow_sql, deny_sql, unclear_sql),
            allow_args + deny_args + unclear_args):
        print("    %-56s %8s" % (value[:56], thousands(count)))

    print("\n== Ersatzregel für leeren itemtype (§1) ==\n")
    print("  importieren nur, wenn instrument gesetzt UND (pages gesetzt ODER Vorschau-PDF)\n")
    has_pdf_column = "has_preview_pdf" in {r[1] for r in db.execute("PRAGMA table_info(products)")}
    pdf_term = "has_preview_pdf=1" if has_pdf_column else "0"
    if not has_pdf_column:
        print("  ACHTUNG: Spalte has_preview_pdf fehlt — Regel ohne PDF-Zweig gerechnet.\n")

    rows = db.execute("""
        SELECT COUNT(*),
          SUM(CASE WHEN instrument IS NOT NULL AND TRIM(instrument)<>'' THEN 1 ELSE 0 END),
          SUM(CASE WHEN instrument IS NOT NULL AND TRIM(instrument)<>''
                    AND (pages IS NOT NULL OR %s) THEN 1 ELSE 0 END),
          SUM(CASE WHEN instrument IS NOT NULL AND TRIM(instrument)<>'' AND pages IS NOT NULL
                   THEN 1 ELSE 0 END),
          SUM(CASE WHEN instrument IS NOT NULL AND TRIM(instrument)<>'' AND pages IS NULL
                    AND %s THEN 1 ELSE 0 END)
        FROM products WHERE itemtype IS NULL OR TRIM(itemtype)=''""" % (pdf_term, pdf_term)
    ).fetchone()
    empty_total, with_instrument, rescued, via_pages, via_pdf = rows
    print("  Zeilen mit leerem itemtype        %10s" % thousands(empty_total))
    print("    davon instrument gesetzt        %10s  %5.1f%%"
          % (thousands(with_instrument), 100.0 * with_instrument / empty_total))
    print("    davon gerettet (Regel erfüllt)  %10s  %5.1f%%"
          % (thousands(rescued), 100.0 * rescued / empty_total))
    print("      über pages                    %10s" % thousands(via_pages))
    print("      nur über Vorschau-PDF         %10s" % thousands(via_pdf))
    print("    endgültig verworfen             %10s  %5.1f%%"
          % (thousands(empty_total - rescued), 100.0 * (empty_total - rescued) / empty_total))


BASKET_SQL = """
  COALESCE((SELECT MIN(json_extract(j.value,'$.amount')*json_extract(j.value,'$.price'))
            FROM json_each(p.bulk_prices) j),
           p.price*MAX(COALESCE(p.minquantity,1),1))
"""


def attach_all(db):
    db.execute("ATTACH DATABASE ? AS m", ("file:%s?mode=ro" % MATCH_DB,))


def cascade():
    """Die drei inhaltlichen Filter nacheinander. Die Wertschwelle ist
    gestrichen — der Server hat 44 GB frei, Platte ist keine Randbedingung."""
    lists = load_lists()
    db = sqlite3.connect("file:%s?mode=ro" % SIGHTING_DB, uri=True)
    attach_all(db)
    noten_frag, noten_args = noten_sql(lists)

    if "available_for_sale" not in {r[1] for r in db.execute("PRAGMA table_info(products)")}:
        sys.exit("Spalte available_for_sale fehlt — erst stretta_backfill.py run.")

    db.execute("CREATE TEMP TABLE dup AS "
               "SELECT DISTINCT s.handle FROM m.stretta_keys s "
               "JOIN m.smd_keys k ON k.norm=s.norm AND k.sname=s.sname WHERE s.strict=1")
    db.execute("CREATE INDEX temp.ix_dup ON dup(handle)")
    print("SMD-Dubletten (nur strict=1): %s Stretta-Zeilen\n"
          % thousands(db.execute("SELECT COUNT(*) FROM dup").fetchone()[0]))

    ersatz = ("(p.itemtype IS NULL OR TRIM(p.itemtype)='') AND p.instrument IS NOT NULL "
              "AND TRIM(p.instrument)<>'' AND (p.pages IS NOT NULL OR p.has_preview_pdf=1)")
    stages = [
        ("Rohbestand", "1=1", []),
        ("+ verkäuflich", "p.available_for_sale=1", []),
        ("+ Noten (Listen + Buch-Regel + Ersatzregel)",
         "p.available_for_sale=1 AND (%s OR (%s))" % (noten_frag, ersatz), noten_args),
        ("+ keine SMD-Dublette",
         "p.available_for_sale=1 AND (%s OR (%s)) "
         "AND p.handle NOT IN (SELECT handle FROM dup)" % (noten_frag, ersatz), noten_args),
    ]

    print("== Kaskade ==\n")
    print("  %-44s %12s %12s" % ("Stufe", "Zeilen", "Platz @4,0KB"))
    previous = None
    for label, condition, args in stages:
        count = db.execute(
            "SELECT COUNT(*) FROM products p WHERE %s" % condition, args).fetchone()[0]
        delta = "" if previous is None else "  (%+s)" % thousands(count - previous)
        print("  %-44s %12s %9.2f GB%s"
              % (label, thousands(count), count * BYTES_PER_ROW / 1024 ** 3, delta))
        previous = count

    print("\n== Endbestand je Verlag (20 größte) ==\n")
    condition, args = stages[3][1], stages[3][2]
    print("  %-34s %12s %12s" % ("Verlag", "Zeilen", "Platz"))
    for vendor, count in db.execute(
        "SELECT COALESCE(NULLIF(TRIM(p.vendor),''),'(leer)') v, COUNT(*) c FROM products p "
        "WHERE %s GROUP BY v ORDER BY c DESC LIMIT 20" % condition, args):
        print("  %-34s %12s %9.2f GB"
              % (vendor[:34], thousands(count), count * BYTES_PER_ROW / 1024 ** 3))


def sample(count=200, seed=20260815):
    """Nach Verlagen geschichtet: höchstens 10 Zeilen je Verlag, damit nicht
    ein Bearbeitungsverlag die Stichprobe dominiert."""
    lists = load_lists()
    allow, deny, unclear = set(lists["allow"]), set(lists["deny"]), set(lists["unclear"])
    db = sighting()

    vendors = [row[0] for row in db.execute(
        "SELECT COALESCE(NULLIF(TRIM(vendor),''),'(leer)') v, COUNT(*) c "
        "FROM products GROUP BY v ORDER BY c DESC LIMIT 25")]
    per_vendor = max(1, count // (len(vendors) + 5))

    columns = ("handle, text_title, vendor, itemtype, instrument, pages, price, slug_de, "
               "available_for_sale, has_preview_pdf")
    random.seed(seed)
    chosen = []
    for vendor in vendors:
        rows = db.execute(
            "SELECT %s FROM products WHERE COALESCE(NULLIF(TRIM(vendor),''),'(leer)')=?"
            % columns, (vendor,)).fetchall()
        chosen += random.sample(rows, min(per_vendor, len(rows)))

    tail = db.execute(
        "SELECT %s FROM products WHERE COALESCE(NULLIF(TRIM(vendor),''),'(leer)') NOT IN %s"
        % (columns, in_clause(vendors)[0]), vendors).fetchall()
    chosen += random.sample(tail, min(count - len(chosen), len(tail)))
    random.shuffle(chosen)

    print("Geschichtete Stichprobe: %d Zeilen, höchstens %d je Verlag, seed %d" % (
        len(chosen), per_vendor, seed))
    print("Filter-Spalte: JA = Allowlist oder Ersatzregel erfüllt; sonst NEIN mit Grund.\n")
    for index, row in enumerate(chosen, 1):
        (handle, title, vendor, itemtype, instrument, pages, price, slug,
         sellable, has_pdf) = row
        verdict, reason = verdict_for(itemtype, instrument, pages, has_pdf,
                                      allow, deny, unclear)
        print("%3d %-4s %-8s %-9s %-36s | %-28s | %s"
              % (index, verdict, reason, handle, (title or "(KEIN TITEL)")[:36],
                 vendor[:28], key[:32] or "(leer)"))
        print("    %-44s S=%-6s %8.2f EUR  afs=%s pdf=%s  /%s.html"
              % ((instrument or "-")[:44], pages or "-", price or 0,
                 sellable, has_pdf, slug or "x-nr-%s" % handle))


def buch_rule(count=20, seed=20260815):
    """Was die riskanteste der drei Regeln real hereinholt."""
    lists = load_lists()
    rule = lists["conditional_allow"][0]["sql"]
    db = sighting()
    total = db.execute("SELECT COUNT(*) FROM products WHERE TRIM(itemtype)='Buch'").fetchone()[0]
    hit = db.execute("SELECT COUNT(*) FROM products WHERE %s" % rule).fetchone()[0]
    sellable = db.execute(
        "SELECT COUNT(*) FROM products WHERE %s AND available_for_sale=1" % rule).fetchone()[0]
    libretto = db.execute(
        "SELECT COUNT(*) FROM products WHERE TRIM(itemtype)='Buch' "
        "AND lower(instrument) LIKE '%libretto%'").fetchone()[0]
    print("== Buch-Regel ==\n")
    print("  itemtype = 'Buch' gesamt          %10s" % thousands(total))
    print("  davon Regel erfüllt               %10s  %5.1f%%" % (thousands(hit), 100.0 * hit / total))
    print("  davon verkäuflich                 %10s" % thousands(sellable))
    print("  Ausnahme instrument~Libretto      %10s" % thousands(libretto))
    print("  ohne Besetzung (bleibt DENY)      %10s" % thousands(total - hit - libretto))

    print("\n  Verlagsverteilung der hereingeholten Zeilen (Top 20):")
    print("    %-36s %9s %9s" % ("Verlag", "Zeilen", "% v. Regel"))
    for vendor, n in db.execute(
        "SELECT COALESCE(NULLIF(TRIM(vendor),''),'(leer)') v, COUNT(*) c FROM products "
        "WHERE %s GROUP BY v ORDER BY c DESC LIMIT 20" % rule):
        print("    %-36s %9s %8.1f%%" % (vendor[:36], thousands(n), 100.0 * n / hit))

    rows = db.execute(
        "SELECT handle, text_title, vendor, instrument, pages, price, slug_de, "
        "available_for_sale FROM products WHERE %s" % rule).fetchall()
    random.seed(seed)
    print("\n  Stichprobe %d zum Gegenprüfen (seed %d):\n" % (count, seed))
    for index, row in enumerate(random.sample(rows, min(count, len(rows))), 1):
        handle, title, vendor, instrument, pages, price, slug, sellable_row = row
        print("  %2d. %-42s | %-26s" % (index, (title or "(kein Titel)")[:42], (vendor or "")[:26]))
        print("      %-46s S=%-6s %7.2f EUR afs=%s" % ((instrument or "-")[:46], pages or "-",
                                                       price or 0, sellable_row))
        print("      https://www.stretta-music.de/%s.html" % (slug or "x-nr-%s" % handle))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "lists"
    if command == "lists":
        build_lists()
    elif command == "rest":
        rest_analysis()
    elif command == "cascade":
        cascade()
    elif command == "buch":
        buch_rule(int(sys.argv[2]) if len(sys.argv) > 2 else 20)
    elif command == "sample":
        sample(int(sys.argv[2]) if len(sys.argv) > 2 else 200,
               int(sys.argv[3]) if len(sys.argv) > 3 else 20260815)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
