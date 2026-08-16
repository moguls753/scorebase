"""Wertet die handgelabelte Notenstichprobe gegen die Filterentscheidung aus
und schreibt die Belegtabelle nach tools/.

    python3 tools/scripts/stretta_label_eval.py

Die Labels stehen als Positionsstring in LABELS und beziehen sich auf die
Reihenfolge von `stretta_filter.py sample 200 20260815`. Gelabelt hat das
erzeugende System (Claude), nicht ein Mensch — jede Zeile trägt die URL,
damit jedes Urteil einzeln widerlegbar ist.

N = Noten, K = keine Noten, U = unklar (nicht aus den Feldern entscheidbar).
"""

import json
import os
import random
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stretta_filter import in_clause, load_lists, thousands, verdict_for  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIGHTING_DB = os.path.join(ROOT, "storage", "stretta-sighting.sqlite3")
OUT_PATH = os.path.join(ROOT, "tools", "stretta-noten-sample-2026-08-15.md")

KEINE_NOTEN = {12, 25, 32, 34, 46, 48, 58, 62, 66, 94, 99, 115, 141, 157}
UNKLAR = {11, 173}
COUNT, SEED = 200, 20260815


def labels():
    return {i: ("K" if i in KEINE_NOTEN else "U" if i in UNKLAR else "N")
            for i in range(1, COUNT + 1)}


def draw():
    """Muss die Ziehung aus stretta_filter.sample exakt reproduzieren."""
    db = sqlite3.connect("file:%s?mode=ro" % SIGHTING_DB, uri=True)
    columns = ("handle, text_title, vendor, itemtype, instrument, pages, price, slug_de, "
               "available_for_sale, has_preview_pdf")
    vendors = [row[0] for row in db.execute(
        "SELECT COALESCE(NULLIF(TRIM(vendor),''),'(leer)') v, COUNT(*) c "
        "FROM products GROUP BY v ORDER BY c DESC LIMIT 25")]
    per_vendor = max(1, COUNT // (len(vendors) + 5))
    random.seed(SEED)
    chosen = []
    for vendor in vendors:
        rows = db.execute(
            "SELECT %s FROM products WHERE COALESCE(NULLIF(TRIM(vendor),''),'(leer)')=?"
            % columns, (vendor,)).fetchall()
        chosen += random.sample(rows, min(per_vendor, len(rows)))
    tail = db.execute(
        "SELECT %s FROM products WHERE COALESCE(NULLIF(TRIM(vendor),''),'(leer)') NOT IN %s"
        % (columns, in_clause(vendors)[0]), vendors).fetchall()
    chosen += random.sample(tail, min(COUNT - len(chosen), len(tail)))
    random.shuffle(chosen)
    return chosen


def filter_verdict(itemtype, instrument, pages, has_pdf, lists):
    return verdict_for(itemtype, instrument, pages, has_pdf,
                       set(lists["allow"]), set(lists["deny"]), set(lists["unclear"]))


# Zweite, getrennte Schicht: 20 Zeilen, die ausschliesslich die Buch-Regel
# hereinholt (stretta_filter.py buch 20). Die alte 200er-Stichprobe enthaelt
# davon nur sieben, zu wenig fuer die riskanteste der drei Regeln.
BUCH_KEINE_NOTEN = {11}   # Tecnica Vocale — Buch ueber Stimmphysiologie
BUCH_UNKLAR = {18}        # ABRSM Theory Exams, Model Answers


def buch_stratum():
    lists = load_lists()
    db = sqlite3.connect("file:%s?mode=ro" % SIGHTING_DB, uri=True)
    rows = db.execute(
        "SELECT handle, text_title, vendor, instrument, pages, price, slug_de, "
        "available_for_sale FROM products WHERE %s" % lists["conditional_allow"][0]["sql"]
    ).fetchall()
    random.seed(SEED)
    chosen = random.sample(rows, 20)
    noten = sum(1 for i in range(1, 21) if i not in BUCH_KEINE_NOTEN and i not in BUCH_UNKLAR)
    print("\n== Zusatzschicht: 20 Zeilen, die NUR die Buch-Regel hereinholt ==\n")
    print("  Noten            %2d" % noten)
    print("  keine Noten      %2d   %s" % (len(BUCH_KEINE_NOTEN),
          ", ".join(str(i) for i in sorted(BUCH_KEINE_NOTEN))))
    print("  unklar           %2d   %s" % (len(BUCH_UNKLAR),
          ", ".join(str(i) for i in sorted(BUCH_UNKLAR))))
    print("  Präzision der Buch-Regel: %.1f%% (%d/20), ohne 'unklar' %.1f%% (%d/19)"
          % (100.0 * noten / 20, noten, 100.0 * noten / 19, noten))
    return chosen


def main():
    lists = load_lists()
    rows = draw()
    mine = labels()
    if len(rows) != COUNT:
        sys.exit("Ziehung lieferte %d statt %d Zeilen" % (len(rows), COUNT))

    matrix = {}
    reasons = {}
    records = []
    for index, row in enumerate(rows, 1):
        (handle, title, vendor, itemtype, instrument, pages, price, slug,
         sellable, has_pdf) = row
        verdict, reason = filter_verdict(itemtype, instrument, pages, has_pdf, lists)
        label = mine[index]
        matrix[(label, verdict)] = matrix.get((label, verdict), 0) + 1
        if label == "N" and verdict == "NEIN":
            reasons[reason] = reasons.get(reason, 0) + 1
        records.append((index, label, verdict, reason, handle, title, vendor,
                        itemtype, instrument, pages, price, slug, sellable, has_pdf))

    print("== Konfusionsmatrix: Handlabel gegen Filter ==\n")
    print("  %-22s %10s %10s %8s" % ("", "Filter JA", "Filter NEIN", "Summe"))
    for label, name in (("N", "Noten (N)"), ("K", "keine Noten (K)"), ("U", "unklar (U)")):
        yes = matrix.get((label, "JA"), 0)
        no = matrix.get((label, "NEIN"), 0)
        print("  %-22s %10d %10d %8d" % (name, yes, no, yes + no))
    total_yes = sum(v for (_, d), v in matrix.items() if d == "JA")
    total_no = sum(v for (_, d), v in matrix.items() if d == "NEIN")
    print("  %-22s %10d %10d %8d" % ("Summe", total_yes, total_no, total_yes + total_no))

    tp = matrix.get(("N", "JA"), 0)
    fp = matrix.get(("K", "JA"), 0) + matrix.get(("U", "JA"), 0)
    fn = matrix.get(("N", "NEIN"), 0)
    precision = tp / (tp + fp) if tp + fp else 0
    recall = tp / (tp + fn) if tp + fn else 0
    print("\n  Präzision (von den importierten sind wirklich Noten): %5.1f%%  (%d/%d)"
          % (100 * precision, tp, tp + fp))
    print("  Recall (von den Noten werden importiert):              %5.1f%%  (%d/%d)"
          % (100 * recall, tp, tp + fn))
    strict_fp = matrix.get(("K", "JA"), 0)
    print("  Präzision, U nicht als Fehler gewertet:                %5.1f%%"
          % (100 * tp / (tp + strict_fp) if tp + strict_fp else 0))

    if reasons:
        print("\n  Recall-Verlust nach Grund (Noten, die der Filter ablehnt):")
        for reason, count in sorted(reasons.items(), key=lambda kv: -kv[1]):
            print("    %-10s %3d  (%.1f%% aller Noten in der Stichprobe)"
                  % (reason, count, 100.0 * count / (tp + fn)))

    unsellable = sum(1 for r in records if r[12] == 0)
    print("\n  Zusätzlich: %d der %d Zeilen sind nicht verkäuflich (Filter 1 greift davor)."
          % (unsellable, COUNT))

    with open(OUT_PATH, "w") as out:
        out.write(HEADER % (COUNT, SEED, tp + fn, 100 * precision, tp, tp + fp,
                            100 * recall, tp, tp + fn))
        out.write("\n| # | Label | Filter | Grund | Handle | Titel | Verlag | itemtype | Besetzung | afs | URL |\n")
        out.write("|---:|:--:|:--:|---|---|---|---|---|---|:--:|---|\n")
        for (index, label, verdict, reason, handle, title, vendor, itemtype,
             instrument, pages, price, slug, sellable, has_pdf) in records:
            flag = "" if (label == "N") == (verdict == "JA") else " ⚠"
            out.write("| %d | %s%s | %s | %s | %s | %s | %s | %s | %s | %s | [Link](https://www.stretta-music.de/%s.html) |\n"
                      % (index, label, flag, verdict, reason, handle,
                         (title or "(kein Titel)").replace("|", "/")[:52],
                         (vendor or "").replace("|", "/")[:26],
                         (itemtype or "(leer)").replace("|", "/")[:34],
                         (instrument or "-").replace("|", "/")[:34],
                         sellable, slug or "x-nr-%s" % handle))
    print("\ngeschrieben: %s" % OUT_PATH)
    buch_stratum()


HEADER = """# Handgelabelte Notenstichprobe (Filterpräzision)

Stand 2026-08-15. Belegt die Zusage aus `docs/stretta-import-plan.md` §1,
der Recall-Verlust werde gemessen und nicht geschätzt.

**Wer gelabelt hat:** ich (Claude), nicht ein Mensch — dasselbe System, das
den Filter gebaut hat. Die Labels sind damit nicht unabhängig. Jede Zeile
trägt die Produkt-URL, damit jedes einzelne Urteil widerlegbar ist.

**Ziehung:** `python3 tools/scripts/stretta_filter.py sample %d %d`, nach
Verlagen geschichtet (höchstens 6 je Verlag über die 25 größten, Rest aus dem
langen Schwanz). Die frühere Cross-Link-Stichprobe war zu 34 %% Marc Reift;
hier stellt kein Verlag mehr als 3 %%.

**Kriterium:** Enthält der Artikel Notentext, den man zum Musizieren benutzt?
Lehrwerke mit Notenbeispielen zählen als Noten, Bücher über Musik nicht,
Libretti und Texthefte nicht, Tonträger und Zubehör nicht.

| | |
|---|---:|
| Noten laut Label | %d |
| Präzision | **%.1f %%** (%d/%d) |
| Recall | **%.1f %%** (%d/%d) |

⚠ markiert die Zeilen, in denen Filter und Label auseinandergehen.
"""


if __name__ == "__main__":
    main()
