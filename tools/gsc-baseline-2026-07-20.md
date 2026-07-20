# GSC-Baseline 2026-07-20

Referenzstand vor der Wirkung von: Canonicalization (Commit `6065170`, 2026-07-17), Sitemap mit 7.254 SMD-Repräsentanten (live seit 2026-07-17 14:46 GMT), Ensemble-Hubs (Commit `1392b6e`, 2026-07-18).

Fenster aller GSC-API-Zahlen: **2026-04-21 .. 2026-07-20** (90 Tage, `--days 90`).
Alle Zahlen unten sind gegengeprüft; wo ein Prüflauf eine frühere Angabe korrigiert hat, steht die korrigierte Zahl und ein Hinweis.

---

## Wie vergleichen

```bash
export GSC_KEY="$HOME/.config/scorebase/gsc-key.json"
cd /home/eike/dev/personal/scorebase/main

# 1) Site-Totale (Nenner für alles andere)
ruby tools/gsc.rb query --dimensions date --days 90 > bydate.json

# 2) Seiten-Dimension (Repräsentanten, Hubs, Seitentypen)
ruby tools/gsc.rb query --dimensions page --days 90 > pages.json

# 3) Query-Dimension (Brand-Split)
ruby tools/gsc.rb query --dimensions query --days 90 > q90.json

# 4) Sitemap-Status
ruby tools/gsc.rb sitemaps

# 5) Repräsentanten-Universum aus der DB
bin/rails runner 'puts Score.active.smd_group_representatives.count'
```

Aggregation immer **impressions-gewichtet** (`sum(position*impressions)/sum(impressions)`), nie Zeilenmittel.

Zu beobachtende Zahlen (Baseline → Erwartung bei Erfolg):

| Kennzahl | Baseline | Quelle | Erwartung bei Wirkung |
|---|---|---|---|
| Distinct SMD-Reps mit ≥1 Impression | 444 / 7.254 (6,12 %) | pages.json ∩ DB-ID-Liste | steigt deutlich |
| Rep-Impressions / -Klicks | 1.334 / 44 | pages.json | steigen |
| Site-Impressions (date dim) | 144.398 | bydate.json | Referenz-Nenner |
| Site-Klicks (date dim) | 5.713 | bydate.json | — |
| Site-Position (gewichtet) | 14,74 | bydate.json | — |
| Non-Brand gesamt, Position | 16,30 | bydate.json − Brand | sinkt |
| Non-Brand gesamt, CTR | 4,48 % | dito | — |
| `/ensembles` Impressions | 0 | pages.json | > 0 sobald in Sitemap |
| Sitemap `indexiert` | 0 (bei 39.121 eingereicht) | `gsc.rb sitemaps` | > 0 |
| crawled-not-indexed | 115.841 (Stand 2026-07-09) | Coverage-Export, nur UI | sinkt |

Der Coverage-Export ist **nicht** über `tools/gsc.rb` reproduzierbar (UI-only). Für einen Vergleich muss er in der GSC-Oberfläche neu exportiert werden.

---

## Snapshot-Grenzen (vor jeder Interpretation lesen)

1. **Query-Anonymisierung.** Die Query-Dimension zeigt nur 41.860 der 144.398 echten Impressions (29,0 %) und 126 der 5.713 Klicks (2,2 %). Jede Aussage aus `q90.json` gilt nur für diesen benannten Ausschnitt und ist systematisch in Richtung schwach rankender Long-Tail-Queries verzerrt.
2. **Coverage-Export-Cap.** GSC deckelt Drilldown-Exporte bei ~1.000 Zeilen. `Tabelle.csv` ist eine **nicht zufällige** Stichprobe (403-Klasse: 1,06 % der Population, Crawl-Daten nur 2026-06-09..06-17). Nur die 5xx-Klasse (72 Zeilen) ist vollständig. Populationsgrößen selbst kommen aus `Diagramm.csv` und sind ungedeckelt.
3. **Coverage-Export endet 2026-07-10**, letzter frische Datenpunkt 2026-07-09; crawled-not-indexed liegt seit 2026-07-01 flach auf 115.841. Der Export liegt also 7–16 Tage vor dem Ship-Datum der Canonicalization → er kann keine der drei Maßnahmen abbilden. Zusätzlich hinkt die GSC-Coverage-Berichterstattung dem Crawl um ca. eine Woche hinterher.
4. **Suchoberfläche.** `gsc.rb query` liefert default `type=web`. Image-Search existiert separat (alle `/scores/`-Seiten: 3.013 Zeilen / 9.113 Impressions / 69 Klicks); discover, news, googleNews, video: 0 Zeilen.
5. **Produktions-Curl.** Paralleles Curlen von scorebase.org liefert 429. Live-Checks seriell laufen lassen, sonst werden Ergebnisse still falsch klassifiziert.

---

## 1. Site-Totale und Brand-Split

```bash
ruby tools/gsc.rb query --dimensions date  --days 90   # 144.398 / 5.713 / pos 14,74 / CTR 3,96 %
ruby tools/gsc.rb query --dimensions page  --days 90   # 149.920 / 5.708 / pos 15,35
ruby tools/gsc.rb query --dimensions query --days 90   # 9.424 Zeilen, 41.860 / 126 / pos 22,91
```

Brand-Definition: Levenshtein ≤ 2 gegen `scorebase` auf alphanormalisierter Query, Länge 6–14 → 11 Queries. Robust: fünf alternative Definitionen (exact-only bis Lev ≤ 3 + `site:`-Operator) ergeben Brand-Impressions 39–43 %, Brand-Position 3,5–3,8, Non-Brand-Position 35,4–37,2.

| Segment | Impressions | Klicks | CTR | Position (gew.) |
|---|---|---|---|---|
| Brand (11 Queries) | 17.814 | 45 | 0,253 % | 3,62 |
| Non-Brand, benannt | 24.046 | 81 | 0,337 % | 37,21 |
| Non-Brand, anonymisiert (Differenz) | 102.538 | 5.587 | 5,45 % | 11,40 |
| **Non-Brand gesamt** | **126.584** | **5.668** | **4,48 %** | **16,30** |

Positionsmasse ist additiv (GSC-Zeilenposition = impressions-gewichtetes Mittel), daher ist die Subtraktion Brand aus den date-dim-Totalen zulässig. Seiten-Dimension als Gegenprobe: Non-Brand gesamt pos 16,93 / CTR 4,29 %.

**Korrektur gegenüber der ursprünglichen Analyse:** „Brand = ~43 % aller Impressions" ist falsch — 42,6 % gilt nur für benannte Query-Zeilen, der Anteil an echten Site-Impressions ist **12,3 %**. Und „Content rankt bei 37,2" ist um Faktor 2,3 daneben: 37,2 beschreibt nur die 19 % der Non-Brand-Impressions, die GSC benennt; die Population liegt bei **16,30**. Die implizierte „Content konvertiert nicht"-Lesart ist um Faktor ~13 daneben (0,337 % benannt vs. 4,48 % tatsächlich).

Gegenprobe in disjunktem Fenster (`--days 7`, 2026-07-13..07-20): 7.357 Impressions / 367 Klicks; Brand 296 Impressions pos 3,48; Non-Brand sichtbar pos 30,22 vs. Non-Brand gesamt pos 14,12. Derselbe 2×-Gap → strukturell, kein 90d-Artefakt.

Offen: 16.371 Impressions auf der navigationalen Query `scorebase` bei Position 3,52 mit nur 42 Klicks liegt weit unter normaler Navigational-CTR (20–40 %). Verdacht auf Rank-Tracker-/Scraper-SERP-Loads. **Nicht verifiziert.**

---

## 2. SMD-Gruppenrepräsentanten (Sitemap-Baseline)

```bash
bin/rails runner 'puts Score.active.smd_group_representatives.count'   # 7254
ruby tools/gsc.rb query --dimensions page --days 90 --filter "page~~/scores/"
```
Join: `^(/de|/en)?/scores/(\d+)/?$` gegen die ID-Menge, **dedupliziert nach Score-ID**.

| | Wert |
|---|---|
| Rep-Universum | 7.254 |
| Distinct Reps mit ≥1 Web-Impression | **444 (6,12 %)** |
| URL-Zeilen | 472 (bare 408 / `/de/` 49 / `/en/` 15) |
| Impressions | 1.334 (1.209 / 99 / 26) |
| Klicks | 44 (43 / 1 / 0) |
| inkl. Image-Search | 453 Reps (6,24 %) / 1.378 Impressions / 44 Klicks |
| Anteil an Site-Impressions | ~0,93 % |

**Korrektur:** die ursprünglich genannten „472 Reps" sind die URL-Zeilenzahl, nicht distinct Scores — 28 Reps erscheinen unter zwei oder drei Locale-Pfaden. Die ebenfalls genannten 6,1 % gehören zur korrekten Zahl 444.

Nebenbefund: `/en/scores/:id` (15 URLs, 26 Impressions) ist indexiert, steht aber nicht in der Sitemap — Duplicate-Content-Variante, siehe `/en`-301-Regel unten.

Kein Ausschluss-Artefakt: alle `/scores/`-Zeilen haben exakt die Form `/scores/N` (25.980), `/de/scores/N` (7.046), `/en/scores/N` (1.168) — keine Slugs, keine Query-Strings, kein Fremdhost. Der Page-Export terminierte natürlich bei 38.757 Zeilen (kein rowLimit-Cap).

---

## 3. Sitemap-Zustand

```bash
curl -sI https://scorebase.org/sitemap.xml.gz          # last-modified: Fri, 17 Jul 2026 14:46:37 GMT
curl -s  https://scorebase.org/sitemap.xml.gz | gunzip | grep -c '<loc>'   # 39121
ruby tools/gsc.rb sitemaps
```

- 39.121 `<loc>`-Einträge, davon 39.052 unique (69 Duplikate).
- 14.508 `/scores/`-Einträge = exakt 7.254 × 2 Locales → die Reps sind seit 2026-07-17 ausgeliefert.
- GSC: `lastSubmitted` 2026-07-20T08:48:50Z, `lastDownloaded` 2026-07-20T08:48:52Z, eingereicht 39.121, **indexiert 0**.
- **0** `/ensembles`-URLs in der ausgelieferten Sitemap, obwohl `config/sitemap.rb:69-117` sie erzeugt → Datei stammt vom 07-17-Build, Ensemble-Hubs shippten am 07-18. Vor der nächsten Messung: Sitemap regenerieren und `/sitemap.xml.gz` einmalig in Cloudflare purgen (Thruster liefert statisch, Rails-Middleware greift nicht).

**Korrektur:** „erstmals von Google abgerufen am 2026-07-20 08:48" ist nicht belegbar — die Sitemaps-API kennt kein First-Fetch-Feld, `lastDownloaded` ist der jüngste Abruf, und der 2-Sekunden-Abstand zu `lastSubmitted` ist die Signatur einer Neueinreichung an diesem Tag. Korrekt: *zuletzt* abgerufen 07-20; die Rep-Version liegt seit 07-17 14:46 GMT öffentlich. `gsc.rb inspect` deckt Sitemap-Dateien nicht ab, ein früherer Abruf ist daher **nicht nachweisbar**.

---

## 4. Hub-Seitentypen

Aggregation aus `pages.json` nach URL-Präfix, Locale-Segment separat.

Composer-Hubs, ohne Locale-Präfix: `/composers` 1 / 78 / 1, `/composers/:slug` 928 / 4.431 / 306, `/composers/:slug/:instrument` 1.335 / 7.655 / 465 → **2.264 Seiten / 12.164 Impressions / 772 Klicks**.
Alle Locales: **2.848 / 13.513 / 841** (`/de` +531/1.219/63, legacy `/en` +53/130/6).

Effizienz, zwei Nenner:

| Seitentyp | Seiten mit Impr. | veröffentlicht | Klicks/impr. Seite | Klicks/veröff. Seite | Impr./veröff. Seite |
|---|---|---|---|---|---|
| `/:instrument/:difficulty` | 34 | 113 | **0,500** | **0,150** | 1,60 |
| Composers | 2.264 | 8.422 | 0,341 | 0,092 | 1,44 |
| Genres | 158 | 630 | 0,316 | 0,079 | — |
| Artists | 1.090 | 2.858 | 0,270 | 0,103 | **1,81** |
| Scores | — | — | 0,141 | — | — |
| Periods | — | 182 | 0,111 | — | — |

**Korrektur:** „Composer-Hubs sind der effizienteste Seitentyp" hält nicht. Die Instrument-Difficulty-Hubs liegen auf **kurzen URLs** (`config/routes.rb:71-75`, `get ":instrument_slug/:difficulty_slug"`, 44 Instrumente × 5 Level) und nicht unter `/instruments/` — eine Präfix-Bucketierung zerlegt sie in ~34 Einzelbuckets (`/cello`, `/piano`, …) und weist der Familie fälschlich 0,000 zu. Als Familie zusammengefasst schlagen sie Composers auf beiden Nennern; Artists schlagen Composers auf dem Veröffentlicht-Nenner. Composers bleiben die größte Familie nach absoluter Reichweite, nicht die effizienteste. Vorbehalt: 113 veröffentlichte Seiten / 17 Klicks — breite Fehlerbalken.

Der Veröffentlicht-Nenner ist der belastbare: 73 % der veröffentlichten Composer-Hubs haben null Impressions und fallen aus dem Impressions-Nenner heraus (Survivorship Bias).

`/ensembles`: 0 Treffer in `pages.json`, im unabhängigen Re-Fetch, in `q90.json` und in allen 10 Coverage-Drilldowns; 0 Vorkommen von „ensembl" in der Live-Sitemap. Seiten sind live (HTTP 200 auf `/ensembles` und `/ensembles/concert-band`). Die Null misst Seitenalter und Sitemap-Stand, **nicht** SEO-Performance — kein gültiger Vergleich mit reifen Seitentypen.

---

## Was NICHT kaputt ist

Populationen aus `gsc_cov/*/Diagramm.csv`, letzte Zeile 2026-07-10:

| Klasse | Population | Status |
|---|---|---|
| 403 blocked | 94.304 | historischer Rückstand, aktuell **kein** Live-403 |
| Blocked by robots.txt | 4.555 | beabsichtigt (Download-Pfade) |
| Page with redirect | 13.720 | beabsichtigte `/en/*` 301-Regel |
| 5xx | 72 | vollständig erledigt, 0 noch 5xx |
| Not found (404) | 4.788 | gelöschte Scores + Sub-Threshold-Hubs |
| Soft 404 | 15 | nicht untersucht |
| Alternate canonical 2.400 / noindex 2.335 / crawled-not-indexed 115.841 / discovered-not-indexed 1.523 | | — |

**5xx (72) — vollständig getestet, nicht gesampelt.** Alle 72 gecurlt: 54 × 200, 11 × 404, 6 × 301, 1 × 410, 1 × 403, **0 noch 5xx**. Der 403 (`/go/smd/1779789`) ist Absicht: `RedirectsController#smd` liefert `head :forbidden` ohne Same-Host-Referrer, `/go/` ist robots-disallowed. Die ursprüngliche Angabe „2 von 3 gesampelt liefern 200" war eine zu dünne Stichprobe; die tatsächliche Rate ist 54/72 → 200 und 100 % nicht-mehr-5xx.

Falle bei der Nachprüfung: naives `cut -d,` auf `Tabelle.csv` erzeugt Phantom-Fehler — mehrere GSC-URLs enthalten Kommas, eine enthält einen eingebetteten Zeilenumbruch (Facette „Various: # Swedish # Norwegian (bokmal)"). Mit echtem CSV-Parser + URL-Escaping lösen sich alle auf.

**Redirects (13.720).** 1.000/1.000 der Stichprobe matchen `^https?://[^/]+/en(/|$)`. Ursache verbatim in `config/routes.rb:24-25`: `get "/en/*path", to: redirect("/%{path}", status: 301)` und `get "/en", to: redirect("/", status: 301)`. Live bestätigt (`/en/scores/400805` → 301 `/scores/400805`).

**403 (94.304) — Mechanismus war falsch beschrieben.** Ein `robots.txt`-Disallow erzeugt niemals 403, sondern die separate Klasse „Blocked by robots.txt" (das ist die 4.555). `ScoresController#serve_file` (`app/controllers/scores_controller.rb:63-101`) hat keinen 403-Zweig, nur `redirect_to` oder `render status: :not_found`. Live-Test von 6 Download-URLs aus der Stichprobe (`/file/pdf`, `/file/mxl`, `?download=true`, `/de/`-Varianten) × 3 User-Agents (curl, Chrome, Googlebot): 302/302/302, 200/200/200, 302/302/302, 200/200/200, 302/302/302, 302/302/302 — **null 403**. Die 94.304 stammen von etwas außerhalb der App (Edge/WAF oder älteres Deploy) und sind veraltet. Kein Live-Bug, aber auch nicht „aktuell beabsichtigt".

**404 (4.788).** Stichprobe = **1.000 Zeilen** (nicht 999; `Tabelle.csv` hat kein trailing newline).

- 851 `/scores/:id` → 670 unique IDs. DB-Join **und** unabhängiger Live-Curl stimmen überein: 293 → 404 (keine Zeile), 377 → 410 (soft-deleted), **0 aktiv**. Gelöschte Scores liefern bereits 410 Gone; GSC bucketet 410 unter „Nicht gefunden (404)". Eine „auf 410 umstellen"-Empfehlung wäre ein No-Op.
- 144 Composer-Zeilen → 115 locale-bereinigte Pfade: 66 bare `/composers/:slug` (alle live 404, alle aus `HubDataBuilder.composers` gefallen) + 49 Instrument-/Pagination-Sub-Pfade. Von deren 47 Basis-Slugs sind **45 live 200** — es sind 404ende Unterseiten lebender Composer-Seiten, keine toten Composer.
- Mechanismen: Facetten-404s (`/composers/sinatra-frank/trombone`) kommen aus `not_found if @total_count < HubDataBuilder::THRESHOLD` auf dem Composer×Instrument-Schnitt, nicht auf der Composer-Summe — 45 der 112 Slugs liegen über THRESHOLD. `?page=N`-404s (`/composers/soderman-august?page=2`) sind `finalize_pagination` (`hub_pages_controller.rb:352-358`), ein bewusster Anti-Soft-404-Guard. Keine dieser Facetten ist von der Elternseite verlinkt (Curl von `/composers/sinatra-frank`: 0 hrefs mit „trombone").
- 5 weitere URLs (Perioden-/Genre-/Filterseiten) 404en, ihre Eltern liefern 200.

**Korrektur:** „Die 404s betreffen null aktuell aktive Seiten" ist widerlegt — `/composers/carmichael-hoagy/trombone` und `/de/composers/lojeski-ed/drums` liefern jetzt 200 mit echter Trefferliste. Hochgerechnet ~10 aktive Seiten über die Population. Außerdem deckte die ursprüngliche Rechnung nur 736 der 1.000 Stichprobenzeilen ab (264 stillschweigend verworfen).

**Der einzige real handlungsfähige Defekt:** 9 der 1.000 gesampelten 404-URLs stehen weiterhin in der Live-Sitemap, 7 davon 404en aktuell:
`/composers/kelly-r/voice`, `/composers/sinatra-frank/trombone`, `/de/composers/boublil-alain/trombone`, `/de/composers/crouch-andrae/voice`, `/de/composers/des-prez-josquin/piano`, `/de/composers/kelly-r/voice`, `/de/composers/sherwin-manning/voice`.
Ursache: der wöchentliche `SitemapRefreshJob` läuft langsamer als der Katalog sich ändert, also bleiben unter THRESHOLD gefallene Composer×Instrument-Kombis bis zum nächsten Lauf beworben.

Hinweis zur Buchhaltung: 404- und Redirect-Klasse sind nicht disjunkt. 109 der 1.000 404-Zeilen sind `/en/*`-URLs — GSC klassifiziert nach dem Post-Redirect-Status. `/en/*` mit lebendem Ziel landet in der Redirect-Klasse, mit soft-deletetem Ziel in der 404-Klasse. Keine der beiden Zahlen misst die Reichweite der `/en`-Regel sauber.

---

## Offene Fragen, die nur Zeit beantwortet

1. Steigt `indexiert` in `gsc.rb sitemaps` über 0? Aktuell 0 von 39.121 eingereichten URLs.
2. Wandern SMD-Reps von 444/7.254 nach oben — und in welchem Verhältnis zu den 14.508 in der Sitemap gelisteten Rep-URLs?
3. Sinkt crawled-not-indexed unter 115.841, sobald ein Coverage-Export nach dem 2026-07-17 vorliegt? Der aktuelle Export kann die Frage strukturell nicht beantworten.
4. Verschwinden die `/en/scores/:id`-Duplikate (15 URLs / 26 Impressions) und schrumpft die 13.720er-Redirect-Klasse, nachdem die Canonicalization greift?
5. Erzeugen die Ensemble-Hubs Impressions — messbar frühestens ~30 Tage nachdem sie in der Sitemap stehen und `/sitemap.xml.gz` an Cloudflare gepurged wurde.
6. Sinkt die Non-Brand-Gesamtposition unter 16,30? Nur die date-dim-Subtraktion ist hier aussagekräftig, nicht der benannte Query-Ausschnitt.
7. Sind die 16.371 `scorebase`-Impressions bei 0,26 % CTR menschliche Brand-Nachfrage oder Rank-Tracker? Unbeantwortet; ohne Server-Logs mit GSC allein nicht entscheidbar.
8. Verschwinden die 94.304 403s aus der Coverage, wenn Google die Download-Pfade neu crawlt? Sie sind live nicht reproduzierbar, also vermutlich Rückstand — bestätigen kann das nur der nächste Export.
