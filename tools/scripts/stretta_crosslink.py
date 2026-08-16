"""Misst die echte Überschneidung zwischen dem Stretta-Katalog, ScoreBases
freien Scores und dem bestehenden SMD-Bestand.

    python3 tools/scripts/stretta_crosslink.py index          # Schlüsseltabellen bauen
    python3 tools/scripts/stretta_crosslink.py report <gsc.json>
    python3 tools/scripts/stretta_crosslink.py sample [n] [seed]   # Stichprobe zum Handlabeln

Baut storage/stretta-match.sqlite3 (gitignored). Sichtungsdatei und
App-Datenbank werden ausschließlich LESEND geöffnet.

Die Matching-Logik ist app/services/smd_match_finder.rb nachgebaut: exakte
Gleichheit des normalisierten Titels PLUS Übereinstimmung des Komponisten-
Nachnamens, Stoppliste für einwortige Gattungstitel. Zwei dokumentierte
Schwächen sind für diese Messung behoben:

  * die Stoppliste war rein englisch — das lateinische Ordinarium fehlte,
    obwohl die freie Seite (CPDL/IMSLP) überwiegend lateinisch ist;
  * normalize() zerlegte "ß" zu einem Leerzeichen (Größe -> "gro e"),
    weil NFKD das Zeichen nicht auflöst. Jetzt "ß" -> "ss".
"""

import collections
import json
import os
import random
import re
import sqlite3
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MATCH_DB = os.path.join(ROOT, "storage", "stretta-match.sqlite3")
SIGHTING_DB = os.path.join(ROOT, "storage", "stretta-sighting.sqlite3")
APP_DB = os.path.join(ROOT, "storage", "development.sqlite3")

# wörtlich aus SmdMatchFinder::GENERIC_FORM_TITLES
GENERIC_FORM_TITLES = set("""
minuet menuet prelude allegro gavotte romance march overture andante
adagio waltz nocturne etude sonata sonatina rondo intermezzo fugue
aria scherzo serenade chorale sinfonia allemande courante sarabande
gigue air musette bagatelle toccata berceuse elegie andantino arietta
barcarolle impromptu mazurka polonaise ballade fantasia pastorale canon
""".split())

# vom Auftrag benannte Ergänzung: lateinisches Ordinarium
ORDINARIUM = {
    "missa", "kyrie", "gloria", "credo", "sanctus", "agnus dei",
    "requiem", "magnificat", "ave maria", "ave verum",
}

# darüber hinaus, von mir ergänzt — Wirkung wird getrennt ausgewiesen
ORDINARIUM_EXTRA = {
    "benedictus", "salve regina", "stabat mater", "te deum", "alleluia",
    "nunc dimittis", "miserere", "pater noster", "tantum ergo",
    "ave verum corpus", "o salutaris hostia", "panis angelicus",
    "veni creator spiritus", "jubilate deo", "cantate domino",
    "laudate dominum", "adoramus te", "o sacrum convivium",
    "dixit dominus", "gloria patri", "amen", "hallelujah", "halleluja",
}

# Echtes Aufführungsmaterial gegen Gebrauchsware. Reihenfolge: erst die
# spezifischen Aufführungsmarker, dann die Gebrauchsmarker — "Chorpartitur,
# Playback-CD" ist Aufführungsmaterial mit Beilage, kein Playback-Artikel.
PERFORMANCE = re.compile(
    r"partitur|stimmensatz|stimmen|stimme|klavierauszug|orgelauszug|chorbuch|"
    r"direktionsstimme|einzelausgabe|marschnotenmappe", re.I)
CONSUMER = re.compile(
    r"\bbuch\b|buch \(|\bcd\b|\bdvd\b|playback|sammelband|lehrbuch|\bschule\b|"
    r"songbook|liederbuch|notenpapier|zubeh|sch[üu]lerheft|lehrerheft|textbuch|"
    r"notenschreibheft|comic|kalender|taschenbuch|hardcover|softcover", re.I)

VOCAL_SOLO = re.compile(
    r"singstimme|gesang|vokal|voice|vocal|sopran|mezzo|\btenor\b|bariton|"
    r"countertenor|\blied\b|liederbuch|songbook", re.I)
CHOIR = re.compile(
    r"chor\b|chöre|choir|choral|chorpartitur|chorbuch|chorstimme|satb|ssaa|"
    r"ttbb|\bssa\b|\bsab\b|\btbb\b|a cappella|kantorei", re.I)


def normalize(text):
    """SmdMatchFinder.normalize plus ß-Behandlung."""
    if not text:
        return ""
    text = text.replace("ß", "ss").replace("ẞ", "SS")
    decomposed = unicodedata.normalize("NFKD", text)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", stripped.lower()).strip()


def surname(name):
    """SmdMatchFinder.surname: vor dem Komma steht der Nachname, sonst das
    letzte Wort."""
    if not name:
        return ""
    head, sep, _ = name.partition(",")
    if sep:
        return normalize(head)
    parts = head.split()
    return normalize(parts[-1]) if parts else ""


def reversed_surname(name):
    """Stretta führt beide Reihenfolgen ohne Komma (Georges Brassens UND
    Brassens Georges). Liefert den Gegenkandidaten, sonst None."""
    if not name or "," in name:
        return None
    parts = name.split()
    if len(parts) < 2:
        return None
    candidate = normalize(parts[0])
    return candidate or None


def free_family(voicing, is_instrumental, instruments):
    """SmdMatchFinder.free_family"""
    if is_instrumental == 1:
        return instrument_family(instruments)
    if is_instrumental == 0 or (voicing or "").strip():
        return "vocal"
    return instrument_family(instruments)


def instrument_family(instruments):
    text = (instruments or "").lower()
    if not text.strip():
        return "other"
    if re.search(r"satb|ssa|ttbb|choir|choral|voice|vocal", text):
        return "vocal"
    if re.search(r"piano|keyboard|organ|harpsichord", text):
        return "piano"
    if re.search(r"guitar|ukulele|\blute\b|banjo|mandolin", text):
        return "guitar"
    if re.search(r"violin|viola|cello|double bass|contrabass|harp", text):
        return "strings"
    if re.search(r"flute|clarinet|sax|oboe|bassoon|trumpet|horn|trombone|tuba|recorder", text):
        return "winds"
    if "orchestra" in text:
        return "orchestra"
    return "other"


def stretta_family(instrument, itemtype):
    """Grobfamilie der Stretta-Zeile. Reihenfolge ist bedeutsam:
    Blasorchester ist band, Streichorchester ist strings — beide enthalten
    'orchester'."""
    text = "%s %s" % (instrument or "", itemtype or "")
    if CHOIR.search(text) or VOCAL_SOLO.search(text):
        return "vocal"
    lowered = text.lower()
    if re.search(r"blasorchester|blasmusik|concert band|brass band|marching band|"
                 r"fanfare|big band|jazzensemble|posaunenchor", lowered):
        return "band"
    if re.search(r"streichorchester|streicher", lowered):
        return "strings"
    if re.search(r"sinfonieorchester|orchester|orchestra|kammerorchester", lowered):
        return "orchestra"
    if re.search(r"klavier|piano|orgel|organ|cembalo|harpsichord|keyboard", lowered):
        return "piano"
    if re.search(r"gitarre|guitar|ukulele|laute|\blute\b|banjo|mandolin", lowered):
        return "guitar"
    if re.search(r"violine|violin|viola|violoncello|cello|kontrabass|"
                 r"double bass|harfe|\bharp\b|streichquartett", lowered):
        return "strings"
    if re.search(r"fl[oö]te|flute|klarinette|clarinet|saxophon|\bsax\b|oboe|fagott|"
                 r"bassoon|trompete|trumpet|\bhorn\b|posaune|trombone|tuba|"
                 r"blockfl|recorder|euphonium", lowered):
        return "winds"
    return "other"


def material_kind(itemtype):
    text = (itemtype or "").strip()
    if not text:
        return "unklar"
    if PERFORMANCE.search(text):
        return "auffuehrung"
    if CONSUMER.search(text):
        return "gebrauch"
    return "unklar"


def page_total(pages_json):
    """custom.pages ist eine Liste (["49","20"] = zweibändig)."""
    if not pages_json:
        return None
    try:
        values = json.loads(pages_json)
    except ValueError:
        return None
    if not isinstance(values, list):
        return None
    total = 0
    for value in values:
        try:
            total += int(str(value).strip())
        except (TypeError, ValueError):
            continue
    return total or None


def thousands(value):
    return format(int(value), ",d").replace(",", ".")


def open_match_db():
    db = sqlite3.connect(MATCH_DB, timeout=120, uri=True)  # uri=True gilt auch für ATTACH
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=OFF")
    return db


def attach_sources(db):
    db.execute("ATTACH DATABASE ? AS sight", ("file:%s?mode=ro" % SIGHTING_DB,))
    db.execute("ATTACH DATABASE ? AS app", ("file:%s?mode=ro" % APP_DB,))


# --------------------------------------------------------------- Indexbau

def build_index():
    if os.path.exists(MATCH_DB):
        os.remove(MATCH_DB)
    for suffix in ("-wal", "-shm"):
        if os.path.exists(MATCH_DB + suffix):
            os.remove(MATCH_DB + suffix)

    db = open_match_db()
    db.execute("ATTACH DATABASE ? AS sight", ("file:%s?mode=ro" % SIGHTING_DB,))
    db.execute("ATTACH DATABASE ? AS app", ("file:%s?mode=ro" % APP_DB,))
    db.executescript("""
      CREATE TABLE stretta_keys (handle TEXT NOT NULL, norm TEXT NOT NULL,
                                 sname TEXT NOT NULL, strict INTEGER NOT NULL);
      CREATE TABLE stretta_meta (handle TEXT PRIMARY KEY, family TEXT, is_choir INTEGER,
                                 is_vocal INTEGER, kind TEXT, pages INTEGER);
      CREATE TABLE smd_keys (id INTEGER NOT NULL, norm TEXT NOT NULL, sname TEXT NOT NULL);
      CREATE TABLE free_keys (score_id INTEGER PRIMARY KEY, norm TEXT NOT NULL,
                              sname TEXT NOT NULL, family TEXT, source TEXT);
    """)

    print("Stretta-Schlüssel ...", flush=True)
    rows, meta, seen = [], [], 0
    cursor = db.execute(
        "SELECT handle, text_title, authors, instrument, itemtype, pages FROM sight.products"
    )
    while True:
        chunk = cursor.fetchmany(50000)
        if not chunk:
            break
        for handle, title, authors_json, instrument, itemtype, pages in chunk:
            seen += 1
            text = "%s %s" % (instrument or "", itemtype or "")
            meta.append((handle, stretta_family(instrument, itemtype),
                         1 if CHOIR.search(text) else 0,
                         1 if (CHOIR.search(text) or VOCAL_SOLO.search(text)) else 0,
                         material_kind(itemtype), page_total(pages)))
            key = normalize(title)
            if not key or not authors_json:
                continue
            try:
                entries = json.loads(authors_json)
            except ValueError:
                continue
            names = [e["name"] for e in entries
                     if isinstance(e, dict) and e.get("role") == "author" and e.get("name")]
            variants = set()
            for name in names:
                strict_name = surname(name)
                if strict_name:
                    variants.add((strict_name, 1))
                other = reversed_surname(name)
                if other and other != strict_name:
                    variants.add((other, 0))
            for sname, strict in variants:
                rows.append((handle, key, sname, strict))
        db.executemany("INSERT INTO stretta_keys VALUES (?,?,?,?)", rows)
        db.executemany("INSERT INTO stretta_meta VALUES (?,?,?,?,?,?)", meta)
        db.commit()
        rows, meta = [], []
        print("  %s Produkte" % thousands(seen), flush=True)

    print("SMD-Schlüssel ...", flush=True)
    rows = []
    for score_id, title, composer, artist in db.execute(
        "SELECT id, title, composer, artist FROM app.scores "
        "WHERE source='smd' AND deleted_at IS NULL"
    ):
        key = normalize(title)
        if not key:
            continue
        for name in {surname(composer), surname(artist)}:
            if name:
                rows.append((score_id, key, name))
    db.executemany("INSERT INTO smd_keys VALUES (?,?,?)", rows)
    db.commit()
    print("  %s Schlüssel" % thousands(len(rows)), flush=True)

    print("Freie Scores ...", flush=True)
    rows = []
    for score_id, title, composer, voicing, instrumental, instruments, source in db.execute(
        "SELECT id, title, composer, voicing, is_instrumental, instruments, source "
        "FROM app.scores WHERE source<>'smd' AND deleted_at IS NULL"
    ):
        key = normalize(title)
        name = surname(composer)
        rows.append((score_id, key, name,
                     free_family(voicing, instrumental, instruments), source))
    db.executemany("INSERT INTO free_keys VALUES (?,?,?,?,?)", rows)
    db.commit()
    print("  %s freie Scores" % thousands(len(rows)), flush=True)

    print("Indizes ...", flush=True)
    db.executescript("""
      CREATE INDEX ix_stretta ON stretta_keys(norm, sname);
      CREATE INDEX ix_stretta_handle ON stretta_keys(handle);
      CREATE INDEX ix_stretta_sname ON stretta_keys(sname);
      CREATE INDEX ix_smd ON smd_keys(norm, sname);
      CREATE INDEX ix_free ON free_keys(norm, sname);
    """)
    db.commit()
    print("fertig: %s (%.0f MB)" % (MATCH_DB, os.path.getsize(MATCH_DB) / 1024.0 ** 2))


# ------------------------------------------------------------- Hilfsabfragen

def stoplist_clause(column, extended):
    words = GENERIC_FORM_TITLES | ORDINARIUM | (ORDINARIUM_EXTRA if extended else set())
    return "%s NOT IN (%s)" % (column, ",".join("?" * len(words))), sorted(words)


def matched_free_scores(db, strict_only, extended):
    """score_id -> Trefferzahl bei Stretta."""
    clause, words = stoplist_clause("f.norm", extended)
    strict = " AND s.strict=1" if strict_only else ""
    sql = ("SELECT f.score_id, COUNT(DISTINCT s.handle) FROM free_keys f "
           "JOIN stretta_keys s ON s.norm=f.norm AND s.sname=f.sname%s "
           "WHERE f.norm<>'' AND f.sname<>'' AND %s GROUP BY f.score_id" % (strict, clause))
    return dict(db.execute(sql, words))


# ------------------------------------------------------------------ Bericht

def clicks_by_score(gsc_path):
    clicks = collections.Counter()
    for row in json.load(open(gsc_path)):
        found = re.search(r"/scores/(\d+)", row["keys"][0])
        if found:
            clicks[int(found.group(1))] += row["clicks"]
    return clicks


def auftrag1(db, clicks):
    print("\n" + "=" * 78)
    print("AUFTRAG 1 — Cross-Link-Überschneidung freie Scores x Stretta")
    print("=" * 78)

    total_free = db.execute("SELECT COUNT(*) FROM free_keys").fetchone()[0]
    usable = db.execute("SELECT COUNT(*) FROM free_keys WHERE norm<>'' AND sname<>''").fetchone()[0]
    print("\nFreie Scores aktiv: %s, davon mit Titel UND Komponistennachname: %s (%.1f%%)"
          % (thousands(total_free), thousands(usable), 100.0 * usable / total_free))

    variants = {}
    for label, strict_only, extended in (
        ("streng (nur surname wie SmdMatchFinder)", True, False),
        ("+ Namensumkehr auf der Stretta-Seite", False, False),
        ("+ erweiterte Ordinarium-Stoppliste", False, True),
    ):
        hits = matched_free_scores(db, strict_only, extended)
        variants[label] = hits
        clicked = sum(clicks.get(i, 0) for i in hits)
        print("\n  %s" % label)
        print("    freie Scores mit >=1 Stretta-Treffer: %s  (%.1f%% von %s)"
              % (thousands(len(hits)), 100.0 * len(hits) / usable, thousands(usable)))
        print("    Trefferpaare gesamt:                  %s" % thousands(sum(hits.values())))
        print("    davon GSC-Klicks abgedeckt:           %s" % thousands(clicked))

    main = variants["+ Namensumkehr auf der Stretta-Seite"]

    total_clicks = sum(clicks.values())
    free_ids = {row[0] for row in db.execute("SELECT score_id FROM free_keys")}
    free_clicks = sum(count for i, count in clicks.items() if i in free_ids)
    covered = sum(clicks.get(i, 0) for i in main)
    print("\n  Klickgewichtung (GSC, 90 Tage) — UNTERGRENZE für den Sofortertrag,")
    print("  ausdrücklich KEIN Auswahlkriterium: der heutige Traffic ist endogen, er")
    print("  spiegelt nur, was gerade im Index liegt (CPDL-lastig, daher Chor/Latein).")
    print("  Danach auszuwählen wäre ein Zirkelschluss.")
    print("    Klicks auf /scores/ gesamt:        %s" % thousands(total_clicks))
    print("    davon auf freie Scores:            %s" % thousands(free_clicks))
    print("    davon mit Stretta-Treffer:         %s  (%.1f%% des freien Traffics)"
          % (thousands(covered), 100.0 * covered / free_clicks if free_clicks else 0))

    clicked_free = [i for i in free_ids if clicks.get(i, 0) > 0]
    clicked_hit = [i for i in clicked_free if i in main]
    print("    freie Scores mit >=1 Klick:        %s" % thousands(len(clicked_free)))
    print("    davon mit Stretta-Treffer:         %s  (%.1f%%)"
          % (thousands(len(clicked_hit)),
             100.0 * len(clicked_hit) / len(clicked_free) if clicked_free else 0))

    print("\n  Verteilung der Trefferzahl je freiem Score (Variante 2):")
    buckets = collections.Counter()
    for count in main.values():
        if count == 1:
            buckets["1"] += 1
        elif count <= 3:
            buckets["2-3"] += 1
        elif count <= 10:
            buckets["4-10"] += 1
        elif count <= 50:
            buckets["11-50"] += 1
        else:
            buckets[">50"] += 1
    for label in ("1", "2-3", "4-10", "11-50", ">50"):
        count = buckets[label]
        print("    %-8s %8s Scores  %5.1f%%" % (label, thousands(count),
                                                100.0 * count / len(main) if main else 0))
    ordered = sorted(main.values(), reverse=True)
    print("    Median %d, Mittelwert %.1f, Maximum %s"
          % (ordered[len(ordered) // 2], sum(ordered) / len(ordered), thousands(ordered[0])))

    print("\n  Familien-Kompatibilität der Treffer (Boost-Kriterium aus SmdMatchFinder):")
    clause, words = stoplist_clause("f.norm", False)
    same, different = db.execute(
        "SELECT SUM(gleich), SUM(1-gleich) FROM ("
        "  SELECT DISTINCT f.score_id, s.handle,"
        "         CASE WHEN f.family=m.family AND f.family<>'other' THEN 1 ELSE 0 END gleich"
        "  FROM free_keys f JOIN stretta_keys s ON s.norm=f.norm AND s.sname=f.sname "
        "  JOIN stretta_meta m ON m.handle=s.handle "
        "  WHERE f.norm<>'' AND f.sname<>'' AND " + clause + ")", words).fetchone()
    total_pairs = (same or 0) + (different or 0)
    print("    gleiche Familie: %s von %s Paaren (%.1f%%)"
          % (thousands(same or 0), thousands(total_pairs),
             100.0 * (same or 0) / total_pairs if total_pairs else 0))

    print("\n  Nur-Komponist-Treffer (Hub-Potenzial statt Cross-Link):")
    composer_hits = {
        row[0] for row in db.execute(
            "SELECT DISTINCT f.score_id FROM free_keys f "
            "WHERE f.sname<>'' AND EXISTS (SELECT 1 FROM stretta_keys s WHERE s.sname=f.sname)"
        )
    }
    extra = composer_hits - set(main)
    print("    freie Scores, deren Komponist bei Stretta vorkommt: %s (%.1f%%)"
          % (thousands(len(composer_hits)), 100.0 * len(composer_hits) / usable))
    print("    davon OHNE Werktreffer (nur Hub):                   %s (%.1f%%)"
          % (thousands(len(extra)), 100.0 * len(extra) / usable))
    print("    deren GSC-Klicks:                                   %s"
          % thousands(sum(clicks.get(i, 0) for i in extra)))
    return main


def auftrag2(db):
    print("\n" + "=" * 78)
    print("AUFTRAG 2 — Überschneidung Stretta x bestehender SMD-Bestand")
    print("=" * 78)

    clause, words = stoplist_clause("s.norm", False)
    total = db.execute("SELECT COUNT(*) FROM stretta_meta").fetchone()[0]
    overlap = db.execute(
        "SELECT COUNT(DISTINCT s.handle) FROM stretta_keys s "
        "JOIN smd_keys m ON m.norm=s.norm AND m.sname=s.sname WHERE " + clause, words
    ).fetchone()[0]
    print("\nStretta-Zeilen gesamt:            %s" % thousands(total))
    print("davon Werk bereits als SMD-Zeile: %s  (%.1f%%)"
          % (thousands(overlap), 100.0 * overlap / total))

    db.execute("DROP TABLE IF EXISTS overlap_handles")
    db.execute("CREATE TABLE overlap_handles (handle TEXT PRIMARY KEY)")
    db.execute(
        "INSERT OR IGNORE INTO overlap_handles "
        "SELECT DISTINCT s.handle FROM stretta_keys s "
        "JOIN smd_keys m ON m.norm=s.norm AND m.sname=s.sname WHERE " + clause, words)
    db.commit()

    print("\n  Nach Verlag (Top 20 nach Zeilen):")
    print("    %-34s %10s %10s %8s" % ("Verlag", "Zeilen", "überlappt", "Anteil"))
    for vendor, rows_, hit in db.execute("""
        SELECT COALESCE(NULLIF(TRIM(p.vendor),''),'(leer)') v, COUNT(*) n,
               SUM(CASE WHEN o.handle IS NOT NULL THEN 1 ELSE 0 END) h
        FROM sight.products p LEFT JOIN overlap_handles o ON o.handle=p.handle
        GROUP BY v ORDER BY n DESC LIMIT 20"""):
        print("    %-34s %10s %10s %7.1f%%"
              % (vendor[:34], thousands(rows_), thousands(hit), 100.0 * hit / rows_))

    print("\n  Nach itemtype (Top 15 nach Zeilen):")
    print("    %-34s %10s %10s %8s" % ("itemtype", "Zeilen", "überlappt", "Anteil"))
    for itemtype, rows_, hit in db.execute("""
        SELECT COALESCE(NULLIF(TRIM(p.itemtype),''),'(leer)') t, COUNT(*) n,
               SUM(CASE WHEN o.handle IS NOT NULL THEN 1 ELSE 0 END) h
        FROM sight.products p LEFT JOIN overlap_handles o ON o.handle=p.handle
        GROUP BY t ORDER BY n DESC LIMIT 15"""):
        print("    %-34s %10s %10s %7.1f%%"
              % (itemtype[:34], thousands(rows_), thousands(hit), 100.0 * hit / rows_))

    print("\n  Warenkörbe der überschneidenden Zeilen (Stretta EUR):")
    for label, where in (("überlappend", "o.handle IS NOT NULL"),
                         ("nicht überlappend", "o.handle IS NULL")):
        values = [row[0] for row in db.execute(
            "SELECT p.expected_basket FROM sight.products p "
            "LEFT JOIN overlap_handles o ON o.handle=p.handle "
            "WHERE %s AND p.expected_basket IS NOT NULL ORDER BY p.expected_basket" % where)]
        if not values:
            continue
        print("    %-20s %10s Zeilen   Mittel %7.2f EUR   Median %7.2f EUR"
              % (label, thousands(len(values)), sum(values) / len(values),
                 values[len(values) // 2]))

    print("\n  Hal Leonard im Detail:")
    for label, condition in (("alle HL-Zeilen", "1=1"),
                             ("HL überlappend", "o.handle IS NOT NULL"),
                             ("HL nicht überlappend", "o.handle IS NULL")):
        count, avg = db.execute("""
            SELECT COUNT(*), AVG(p.expected_basket) FROM sight.products p
            LEFT JOIN overlap_handles o ON o.handle=p.handle
            WHERE p.vendor='Hal Leonard' AND %s""" % condition).fetchone()
        print("    %-24s %10s Zeilen   Mittel %7.2f EUR" % (label, thousands(count), avg or 0))

    smd_avg = db.execute(
        "SELECT AVG(price_usd), COUNT(*) FROM app.scores "
        "WHERE source='smd' AND deleted_at IS NULL AND price_usd>0").fetchone()
    print("\n    SMD-Vergleich: Mittelwert %.2f USD über %s Zeilen mit Preis"
          % (smd_avg[0] or 0, thousands(smd_avg[1])))
    print("    (EUR und USD sind NICHT umgerechnet — kein belegter Kurs vorhanden.)")


def auftrag3(db, matched_handles_table):
    print("\n" + "=" * 78)
    print("AUFTRAG 3 — Wert je Zeile und Katalogqualität nach Verlag (Top 50)")
    print("=" * 78)
    print("\n  Auff%  = echtes Aufführungsmaterial (Partitur/Stimmen/Klavierauszug/Chorpartitur)")
    print("  Gebr%  = Gebrauchsware (Buch, CD, Playback, Sammelband, Schule)")
    print("  Rest zu 100 %% ist 'unklar' — vor allem der Sammelwert 'Noten'.")
    print("  Zugew% = Anteil außerhalb vocal/piano, den beiden Familien, die der freie")
    print("           Katalog schon dicht besetzt (73,2 %% vocal, 14,2 %% piano).\n")
    print("  %-30s %8s %7s %6s %6s %6s %6s %6s %6s %6s"
          % ("Verlag", "Zeilen", "EUR/Zl", "Auff%", "Gebr%", "ISMN%", "ØSeit", "MinQ%",
             "Xlink%", "Zugew%"))
    for row in db.execute("""
        SELECT COALESCE(NULLIF(TRIM(p.vendor),''),'(leer)') v,
               COUNT(*) n,
               COALESCE(SUM(p.expected_basket),0) korb,
               AVG(CASE WHEN m.kind='auffuehrung' THEN 1.0 ELSE 0 END)*100 auff,
               AVG(CASE WHEN m.kind='gebrauch'    THEN 1.0 ELSE 0 END)*100 gebr,
               AVG(CASE WHEN p.ismn IS NOT NULL AND TRIM(p.ismn)<>'' THEN 1.0 ELSE 0 END)*100 ismn,
               AVG(m.pages) seiten,
               AVG(CASE WHEN p.minquantity>1 THEN 1.0 ELSE 0 END)*100 minq,
               SUM(CASE WHEN x.handle IS NOT NULL THEN 1 ELSE 0 END)*100.0/COUNT(*) xlink,
               AVG(CASE WHEN m.family NOT IN ('vocal','piano') THEN 1.0 ELSE 0 END)*100 zugew
        FROM sight.products p
        JOIN stretta_meta m ON m.handle=p.handle
        LEFT JOIN %s x ON x.handle=p.handle
        GROUP BY v ORDER BY n DESC LIMIT 50""" % matched_handles_table):
        (vendor, count, basket, auff, gebr, ismn, seiten, minq, xlink, zugew) = row
        print("  %-30s %8s %7.2f %5.1f%% %5.1f%% %5.1f%% %6.0f %5.1f%% %5.2f%% %5.1f%%"
              % (vendor[:30], thousands(count), basket / count, auff or 0, gebr or 0,
                 ismn or 0, seiten or 0, minq or 0, xlink or 0, zugew or 0))

    print("\n  Familienverteilung: freier Katalog gegen Stretta gesamt")
    print("    %-12s %12s %8s %14s %8s" % ("Familie", "frei", "Anteil", "Stretta", "Anteil"))
    free_total = db.execute("SELECT COUNT(*) FROM free_keys").fetchone()[0]
    stretta_total = db.execute("SELECT COUNT(*) FROM stretta_meta").fetchone()[0]
    free_by = dict(db.execute("SELECT family, COUNT(*) FROM free_keys GROUP BY 1"))
    stretta_by = dict(db.execute("SELECT family, COUNT(*) FROM stretta_meta GROUP BY 1"))
    for family in sorted(set(free_by) | set(stretta_by),
                         key=lambda f: -stretta_by.get(f, 0)):
        free_n, stretta_n = free_by.get(family, 0), stretta_by.get(family, 0)
        print("    %-12s %12s %7.1f%% %14s %7.1f%%"
              % (family, thousands(free_n), 100.0 * free_n / free_total,
                 thousands(stretta_n), 100.0 * stretta_n / stretta_total))
    print("\n    Achtung: die freie Seite kann 'band' gar nicht annehmen — die aus")
    print("    SmdMatchFinder übernommene instrument_family() kennt die Kategorie nicht.")
    print("    Freie Blasorchesterstücke landen in 'other'. Der band-Zugewinn ist real,")
    print("    aber diese Tabelle überzeichnet ihn.")


def sample(count=50, seed=20260815):
    db = open_match_db()
    attach_sources(db)
    clause, words = stoplist_clause("f.norm", False)
    pairs = db.execute(
        "SELECT f.score_id, s.handle FROM free_keys f "
        "JOIN stretta_keys s ON s.norm=f.norm AND s.sname=f.sname "
        "WHERE f.norm<>'' AND f.sname<>'' AND " + clause, words).fetchall()
    print("Trefferpaare gesamt: %s" % thousands(len(pairs)))
    random.seed(seed)
    chosen = random.sample(pairs, min(count, len(pairs)))
    print("Stichprobe %d, seed %d\n" % (len(chosen), seed))
    for index, (score_id, handle) in enumerate(chosen, 1):
        free = db.execute(
            "SELECT title, composer, source, instruments, voicing FROM app.scores WHERE id=?",
            (score_id,)).fetchone()
        prod = db.execute(
            "SELECT text_title, authors, vendor, itemtype, instrument, price "
            "FROM sight.products WHERE handle=?", (handle,)).fetchone()
        names = []
        if prod and prod[1]:
            try:
                names = [e.get("name") for e in json.loads(prod[1])
                         if isinstance(e, dict) and e.get("role") == "author"]
            except ValueError:
                names = []
        print("%2d. FREI    [%s/%s] %s — %s" % (index, free[2], score_id, free[0], free[1]))
        print("    frei-Bes: %s | voicing %s" % ((free[3] or "-")[:60], free[4] or "-"))
        print("    STRETTA [%s] %s — %s" % (handle, prod[0], " / ".join(n for n in names if n)))
        print("    %s | %s | %s | %.2f EUR"
              % (prod[2], prod[3] or "-", (prod[4] or "-")[:50], prod[5] or 0))
        print("    https://www.stretta-music.de/x-nr-%s.html" % handle)
        print()


def report(gsc_path):
    db = open_match_db()
    attach_sources(db)
    clicks = clicks_by_score(gsc_path)
    main = auftrag1(db, clicks)

    db.execute("DROP TABLE IF EXISTS matched_handles")
    db.execute("CREATE TABLE matched_handles (handle TEXT PRIMARY KEY)")
    clause, words = stoplist_clause("f.norm", False)
    db.execute(
        "INSERT OR IGNORE INTO matched_handles "
        "SELECT DISTINCT s.handle FROM free_keys f "
        "JOIN stretta_keys s ON s.norm=f.norm AND s.sname=f.sname "
        "WHERE f.norm<>'' AND f.sname<>'' AND " + clause, words)
    db.commit()
    hit_rows = db.execute("SELECT COUNT(*) FROM matched_handles").fetchone()[0]
    print("\n  Stretta-Zeilen, die an mindestens einem Treffer beteiligt sind: %s"
          % thousands(hit_rows))

    auftrag2(db)
    auftrag3(db, "matched_handles")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "report"
    if command == "index":
        build_index()
    elif command == "sample":
        sample(int(sys.argv[2]) if len(sys.argv) > 2 else 50,
               int(sys.argv[3]) if len(sys.argv) > 3 else 20260815)
    elif command == "report":
        report(sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
