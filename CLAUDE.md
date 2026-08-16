# ScoreBase

Open source sheet music search engine. Deploys to scorebase.org.

## What Is This?

Sheet music search engine aggregating free public domain scores and commercial catalogs (Sheet Music Direct). Browse, search, download free PDFs or purchase commercial arrangements.

## Data Sources & Importers

ScoreBase aggregates from several sources; importers live in `app/services/`:

- **PDMX** and **OpenScore** (lieder + quartets) — carry music21-derived features (MXL available).
- **CPDL** — `CpdlImporter`, via the MediaWiki API. CPDL is Cloudflare-gated, so requests route through the **CloudflareBypass** accessory. Hardened May 2026: a content gate + post-parse thin-page filter (rejects collection/index pages), `apfilterredir=nonredirects` (no redirect-duplicates), and 5xx retry. Fully deleted-and-re-synced — clean, ~55k rows.
- **IMSLP** — `ImslpImporter`, via IMSLP's worklist API + MediaWiki API over plain HTTP (not Cloudflare-gated). Being extended for composer-prioritized catalog completion — see `docs/superpowers/specs/2026-05-21-imslp-import-design.md`.
- **SMD** (Sheet Music Direct) — commercial catalog.
- **Stretta** — second commercial catalog (German publisher retailer), via its Shopify Storefront GraphQL API. See the Stretta section below.

**CloudflareBypass accessory** (`scorebase-cloudflare-bypass`, port 8000, env `CLOUDFLARE_BYPASS_URL`) solves Cloudflare for scraping — used by `CpdlImporter` and `HttpDownloadable`. FlareSolverr was removed May 2026; CloudflareBypass is the sole bypass.

**SQLite FTS gotcha:** the `scores` table has 6 FTS sync triggers. Any op that *rewrites* the table silently drops them, breaking search — such a migration must drop & recreate all 6 (pattern: `db/migrate/20260517143000_remove_clean_title_from_scores.rb`).

Which ops rewrite is the part worth knowing, because it is also a **production-lock question** — SQLite locks database-wide, so a rewrite blocks every write in the app, not just `scores`:

| Op | Cost on 448k rows | Rewrites? |
|---|---|---|
| `execute "ALTER TABLE scores ADD COLUMN ..."` | ~1ms | no |
| `execute "ALTER TABLE scores RENAME COLUMN a TO b"` | ~3ms | no |
| `execute "ALTER TABLE scores DROP COLUMN ..."` | fast | no |
| Rails `rename_column` | **~50s** | yes |
| Rails `remove_column` | **~50s** | yes |

Rails' SQLite adapter still table-copies for `rename_column`/`remove_column`, but SQLite has done these natively since 3.25/3.35 (we run 3.53) — and native `RENAME COLUMN` rewrites the references *inside* dependent triggers and indexes for you, so no trigger dance is needed. It keeps the old index *names* though, so rename those explicitly. Worked example: `db/migrate/20260719110000_add_last_crawled_at_and_rename_search_columns.rb` — 1.4s where the Rails-idiomatic version measured ~150s.

**Sitemap (commercial pages).** `config/sitemap.rb` lists SMD group representatives (`Score.active.smd_group_representatives`, ~7.3k × 2 locales) via a live query, so the weekly `SitemapRefreshJob` auto-includes newly imported/updated reps. Two operational notes: (1) **Edge caching of `public/` is controlled in the app, not at Cloudflare.** `/sitemap.xml.gz` is served by Rails' `ActionDispatch::Static`, so `config.public_file_server.headers` sets the TTL Cloudflare obeys. It is **1 day**, and the governing rule is that it must stay strictly *below* the weekly rebuild interval — `public/` also holds non-digest-stamped files (sitemap, `robots.txt`, `og-image.png`). It was 1 year (Rails default), which pinned an 8-day-stale sitemap at the edge; lowering it to exactly 1 week did not fix that, it only shortened it: a TTL equal to the rebuild cadence still parks every fresh sitemap behind a stale copy for a full cycle.

**Two caches obey this header, not one** (learned 2026-08-13, after a rebuild stayed invisible). In front of `ActionDispatch::Static` sits **Thruster**, inside the web container — it stamps `x-cache: hit|miss`, keeps its cache in process memory, and has **no purge endpoint**: only restarting the container clears it. Cloudflare is the second layer. So diagnose in three steps, not two:

```bash
ssh root@46.224.124.123 "docker exec <web> ls -laL public/sitemap.xml.gz"   # 1. file on disk
curl -sI --resolve scorebase.org:443:46.224.124.123 https://…/sitemap.xml.gz # 2. origin — check x-cache
curl -sI https://scorebase.org/sitemap.xml.gz                                # 3. edge — check age / cf-cache-status
```

**After an out-of-band rebuild the order is load-bearing:** reboot web *first* (`bin/kamal app boot -r web`), confirm the origin reports `x-cache: miss` and the new `content-length`, and only then purge Cloudflare. Purging first makes Cloudflare re-fetch Thruster's stale copy and re-pin it for the full TTL. Purge URL is the apex, **no `www`** (`www.scorebase.org` does not resolve; the dashboard's placeholder text shows the `www` form and is a trap). No CF Cache Rule is needed; no CF API token in the repo (R2 only), so purges are manual. (2) The sitemap is a single file; total is ~45.6k of the 50,000-URL limit (2026-08-13) (a sitemaps.org protocol cap per *file*, not a ScoreBase choice — it cannot be raised). Crossing it makes sitemap_generator switch to index mode and emit child files at `/sitemaps/sitemapN.xml.gz`. **That is now handled**: `bin/docker-entrypoint` symlinks both `public/sitemap.xml.gz` and the `public/sitemaps` directory, so index mode degrades gracefully instead of silently 404-ing every child. Verified end-to-end (child file serves 200 `application/x-gzip`; path traversal through the link still 404s).

**`lastmod` must stay data-derived.** `sitemap_generator` defaults a missing `:lastmod` to `Time.now`, which stamped the build time on all ~12.6k hub URLs (29% of the file) and claimed every hub changed at once on every weekly run. Google uses `lastmod` only where it is "consistently and verifiably accurate" and otherwise discounts it for the whole sitemap — it is the *only* field it acts on (`<priority>` and `<changefreq>` are documented no-ops). Every hub therefore passes `lastmod:` from a `hub_lastmod` lambda over its own scope; only the 11 static URLs still carry build time. Regression check after touching `config/sitemap.rb`: `grep -o '<lastmod>[^<]*' sitemap.xml | sort -u | wc -l` should be five figures, not four, and no single value should dominate.

**SQLite dump gotcha:** `db:migrate` regenerates `db/structure.sql` via `.schema`, which emits the FTS5 *shadow* tables (`*_fts_data/_idx/_docsize/_config`). Those are auto-created by `CREATE VIRTUAL TABLE` — leaving them in the dump breaks `db:test:prepare`. `structure.sql` is hand-maintained: after a migration, restore the committed version and add only your new objects (Rails can't filter shadow tables on SQLite; `SchemaDumper.ignore_tables` doesn't reach them).

**Ensemble hubs (buyer-query landing pages).** The `smd_category`-keyed ensemble hubs ("Concert Band Sheet Music", "SATB Choir Sheet Music") use a **CURATED** `HubDataBuilder::ENSEMBLE_CATEGORIES` allowlist — `smd_category` is a mixed taxonomy (most values are formats like "Piano Solo"), so it is never auto-derived. New scores in an existing allowlisted category auto-appear via the daily `HubCacheWarmJob`, but a genuinely new `smd_category` requires a one-line edit to the constant.

**Cross-links (free → SMD "Professional Editions"):** `score_smd_matches` is derived data (`BackfillSmdMatchesJob`, title+composer-surname matching via `SmdMatchFinder`). It converges **daily at 12pm** — that recurring run is the mechanism, not a safety net, so an ordinary import needs no manual step. Run it by hand only after a bulk title/composer rewrite you don't want to wait a day for: `bin/kamal app exec --reuse -r web "bin/rails scores:backfill_smd_matches"`. The job takes no arguments and cannot be scoped — a single new SMD row can outrank an existing match on any free score, so every run rebuilds the whole index (~199k SMD rows) and walks every free score (~126k). That is ~14s and one database-wide SQLite write lock during the `delete_all`/`insert_all` transaction. Bad match spotted in prod? Set `suppressed = true` on its row (console one-liner); the converge preserves it forever. Preview matches without writing: `DRY_RUN=1 bin/rails scores:backfill_smd_matches`.

## Two commercial partners

`Score::COMMERCIAL_PARTNERS` is the single place that knows a source is a paid catalogue —
its display name, its currency, and which column holds its price. `COMMERCIAL_SOURCES` is
its keys, and `scope :commercial` / `scope :free` replace the old `exclude_smd`. Adding a
third partner is one hash entry plus its i18n copy; `spec/helpers/scores_helper_spec.rb`
fails the build if the copy is missing, because the alternative is "translation missing"
rendered on the buy button.

**Prices are never converted.** `price_usd` and `price_eur` are separate columns and stay
that way — an exchange rate in the display path is a dependency nobody wants to maintain.
Read them through `display_price` / `price_currency`, never directly.

**`where.not` on a nullable column drops the NULL rows.** This bit twice: `by_pricing("free")`
must keep the 12 priceless SMD rows (hence `NOT (source = ... AND COALESCE(price, 0) > 0)`),
and `ConvergeDuplicatesJob` must write to rows whose `duplicate_of_id` is still NULL. Both
build the condition in Arel — also the only way past Brakeman without an ignore entry.

## Stretta

~1.45M sellable sheet-music products (`Stretta::Classifier` over the full sighting). Full
findings and every measurement in `docs/stretta-implementation-notes.md`; the plan it
corrects is `docs/stretta-import-plan.md`.

**The affiliate URL form is the whole business case.** Measured against the live shop:

```
/leitner-...-nr-148059.html?afl=CODE   -> 200, query string kept
/x-nr-148059.html?afl=CODE             -> 301 to the slug URL, query string DROPPED
```

The second form earns nothing, and with half-yearly settlement the loss would surface in
February. `RedirectsController#stretta` therefore reads `partner_slug` from our own row —
never from the URL, which would be a path injection into stretta-music.de — and checks it
against `\A[a-z0-9][a-z0-9-]*\z` before use.

**The GraphQL API is open; the sitemap is not.** `Net::HTTP` gets `403 cf-mitigated: challenge`
from `stretta-music.de` under every header set tried, while `curl` with the same headers gets
the XML — the gate is on the TLS/HTTP fingerprint. `Stretta::SitemapHarvester` goes through
`CloudflareBypassClient` like CPDL. The API itself answers Ruby directly and needs no bypass.

**`products` is capped at 25,000 elements under every sort key**, so no paginated full pass
exists. Full coverage comes from the sitemap; `sortKey: CREATED_AT` is only for the weekly
new-arrivals pass, where the volume stays far below the cap. `updatedAt` is worthless as a
delta signal — 100% of the catalogue carries a July/August 2026 shop-migration timestamp —
so the price rotation runs on our own `last_crawled_at`.

**`Stretta::Importer::UPDATABLE` is an ownership line, not an insert-only one.** Everything the
mapper derives as a pure function of the product — `instruments`, `voicing`, `smd_category`,
`group_rank`, title, price, `stretta_metadata` — is updatable, so re-running the import over an
existing selection list is itself how an improved scoring vocabulary reaches rows that already
exist; there is no separate re-derive task. What's excluded is what another job or an admin
owns: `composer` (`NormalizeComposersJob` — without the exclusion, every sync writes back the
raw German name it canonicalised the night before, daily), `pedagogical_grade`, `rag_status`,
`is_group_representative`, and `group_key` (a new key moves a row between groups; only
`regroup: true` touches it, and only `BackfillGroupKeysJob` re-picks representatives afterwards).
`last_crawled_at` is written but deliberately outside the timestamped upsert — see the class
comment for why it would otherwise poison every row's `updated_at` on every sync.

**Jobs that select on `*_status: pending` need a source filter.** `rag_status` is the one the
plan flags, but `NormalizeInstrumentsJob` had the same hole: an imported partner row whose
scoring did not map satisfies every one of its conditions, and ~30% of 1.2M rows would have
gone to the LLM. It now starts from `Score.free`. Check any new job of this shape.

**Ligatures have no NFKD decomposition to ASCII.** `ß æ œ ø ł` survived the accent strip, so
`Größe` became `gro e` in a match key and stayed `Größe` in the search column — "grosser gott"
never found "Großer Gott". All of it now goes through `MusicText`, in `normalize`,
`normalize_for_search` and `build_fts5_query` alike (query and index side must agree). After
deploying this, run `BackfillSearchColumnsJob` once — 1,316 existing rows.

## Tech Stack

- Rails 8
- SQLite
- Python/FastAPI RAG service
- ChromaDB + sentence-transformers for embeddings
- LLM for reranking (provider-agnostic)
- Kamal for deployment
- Cloudflare CDN

## Development

```bash
bin/dev              # Start Rails
bundle exec rspec    # Run tests
bin/kamal deploy     # Deploy to production — the maintainer runs this, never the agent
```

**Deploying is the maintainer's job.** Take work to green (rubocop + rspec pass, change verified) and stop there, reporting what is ready. Do not run `bin/kamal deploy`, and do not ask whether to deploy.

## Deployment Topology (Kamal)

**Single Hetzner host (`46.224.124.123`)** — 4 vCPU, 8 GB RAM, 40 GB disk (~€16.65/month). Two Rails roles + one RAG accessory all share this host:

| Container | Memory | Command | Purpose |
|---|---|---|---|
| `web` | 1.5 GB | Puma (default) | Rails web server (1 worker × 3 threads) |
| `job` | 1.5 GB | `bin/jobs` | Solid Queue worker |
| `scorebase-rag` accessory | 3.4 GB | `uvicorn src.api.main:app` | Python/FastAPI RAG service on :8001 |

**Headroom budget.** Limits total `1.5 + 1.5 + 3.4 = 6.4 GB` of 7.6 GB, but real usage is far lower — measured 2026-08-11: 2.9 GB used, **4.7 GB available**. `job` was 1 GB until 2026-08, which left only ~400 MB over its idling worker: that is what OOM-killed a `-r job` one-off and what forced `SmdCrawler::SitemapParser` to stream instead of building a DOM. At 1.5 GB both Rails roles now have comparable headroom (~900 MB over an idle worker), so role choice is about *what the command touches*, not about memory.

**CPU, not RAM, is the scarce one.** The host has 4 vCPU and `web` runs Puma. A full `sitemap:refresh` pins one core at ~100% for hours, which is why the `sitemap` alias runs on `-r job` — Puma kept answering in the measured case (its two workers sat at ~10% each), so treat this as headroom hygiene, not a proven outage.

**Measure `x-runtime`, not wall time, and check the route exists.** Wall time from outside is dominated by the Cloudflare round trip (~230–780ms vs ~65ms straight to the origin with `--resolve`), so it cannot separate a slow server from a slow path. Worse, a 404 is *fast* — `/search?q=` is not a route (search is `scores#index` at `/scores?q=` and `/`), and measuring it produced a confident, wrong "search takes 4ms". Always confirm the status code is 200 before believing a latency number.

**Important consequence:** `bin/kamal app exec --reuse "<cmd>"` (no role flag) runs the command on **both** containers. For read-only dry-runs that's harmless duplication. For mutations, migrations, cleanup tasks, or anything one-shot, **always scope to a single role**:

```bash
bin/kamal app exec --reuse -r web "bin/rails <task>"
```

Use `-r web` for one-off rake tasks (cleanups, dry-runs, sitemap refreshes). Use `-r job` only when the task itself touches background-job state. Existing aliases in `config/deploy.yml` already follow this pattern — `sitemap` is the canonical example:

```yaml
sitemap: app exec --reuse -r web "bin/rails sitemap:refresh:no_ping"
```

Copy that shape when adding new aliases for recurring operations.

**Running one-off Ruby in production — pipe a file over ssh, don't fight the quoting.** `bin/rails runner -` reads the script from stdin, which removes every quoting layer at once. This is the reliable form for anything longer than one expression:

```bash
C=$(ssh root@46.224.124.123 "docker ps --format '{{.Names}}' --filter label=role=web --filter status=running | head -1")
ssh root@46.224.124.123 "docker exec -i $C bin/rails runner -" < script.rb
```

The script is then ordinary Ruby — interpolation, heredocs, double quotes, all fine.

Inline via `bin/kamal app exec --reuse -r web "bin/rails runner \"...\""` still works for a one-liner, but the Ruby then travels through SSH *and* two shell layers, so it must contain **no `"`, no backticks, no `$`, and no `#{}`** — all four are eaten before Ruby sees them, and it surfaces as a confusing mid-script syntax error rather than a quoting complaint. Single quotes and `+` concatenation only. For process memory read `/proc/self/statm`; a shelled-out `ps` needs backticks and will not survive.

**Memory when running one-off commands.** `app exec --reuse` starts a *second* Rails process inside the container alongside the one already running, and the two share the container's cgroup limit. Both roles are now 1.5 GB with their worker idling near 560–720 MB, so either has ~800 MB of headroom; anything memory-hungry beyond that (Nokogiri DOM over a large XML, a big `pluck`) still gets OOM-killed with `docker exit status: 137` and no output. Pick the role by cost, not size: short read-only investigation on `-r web`, anything long or CPU-bound on `-r job` so it cannot slow request serving.

**Other aliases already defined** (in `config/deploy.yml`):

| Alias | What it does |
|---|---|
| `bin/kamal console` | `bin/rails console` (interactive, reuses container) |
| `bin/kamal shell` | `bash` (interactive, reuses container) |
| `bin/kamal dbc` | `bin/rails dbconsole --include-password` |
| `bin/kamal logs` | tail logs (`-r job` to scope to worker) |
| `bin/kamal rag-stats` | `bin/rails rag:stats` — show indexing pipeline state |
| `bin/kamal rag-index` | run one batch of the Python indexer (5000 rows) on the RAG accessory |

## Testing

- Use RSpec for all tests
- Keep tests small and simple
- Focus on behavior, not implementation details
- Aim for ~10-15 examples per service; pin contracts, not enumerations

## Code comments

Default to none. Trust well-named identifiers and types to carry the meaning. Only write a comment when the WHY is non-obvious — a hidden constraint, a workaround, a subtle invariant. Never narrate what the code does; never inline what an enum value means when the name already says it; never write multi-paragraph docstrings. If you're unsure, leave it out.

**A comment is one line.** If it needs a paragraph, it belongs in the commit message or a doc, not the source. Specifically do not write:

- **Justifications for a choice** — "SATB stays because the abbreviation is common in German sheet music", "sort: false keeps the curated order". The code already shows the choice; the reasoning is commit-message material.
- **Restatements of the identifier** — `@ensemble_name stays the raw category, only the display copy is localized` above `@ensemble_name` / `@ensemble_display_name`.
- **Background narration** — how a bug arose, how many rows it hit, what a past migration did.

Keep the one-liner only where a future reader would otherwise reintroduce a bug (`# Cloudflare's challenge interstitial is a 200 with no ld+json`).

Same for tests: **only necessary specs.** One example per behaviour, not per assertion, and no spec that a neighbouring spec already covers.

## Pre-push checks (run before `bin/kamal deploy`)

CI runs these; failing locally first saves the round-trip:

```bash
bin/rubocop -f github     # style + lint; CI fails on any offense
bundle exec rspec         # full test suite
bin/brakeman --no-pager   # static security scan; CI fails on any warning
bundle audit              # gem CVE check
```

**Brakeman and `where` — the one that keeps recurring.** Any string interpolation into a SQL fragment trips `SQL Injection`, even when the interpolated value comes from a frozen constant and the *user* value is a bind. Brakeman cannot see that distinction, so it fails CI and you are left choosing between an ignore entry and a rewrite. Build the fragment with Arel instead and there is nothing to flag:

```ruby
# trips Brakeman — the REPLACE nesting is interpolated, even though `decoys` is a constant
stripped = decoys.inject("LOWER(instruments)") { |sql, _| "REPLACE(#{sql}, ?, ' ')" }
where("#{stripped} LIKE ?", *decoys, "%#{needle}%")

# clean, same SQL, same plan (Score.instruments_without)
node = decoys.inject(arel_table[:instruments].lower) do |acc, decoy|
  Arel::Nodes::NamedFunction.new("REPLACE", [ acc, Arel::Nodes.build_quoted(decoy), Arel::Nodes.build_quoted(" ") ])
end
where(node.matches("%#{needle}%"))
```

`config/brakeman.ignore` holds three genuinely-reviewed exceptions (an external redirect, two deliberate SSL bypasses). Adding a fourth for interpolated SQL is the wrong move — the rewrite is a few lines and removes the question permanently.

If you only touched a few files, scope rubocop to them (`bin/rubocop app/... spec/...`) — full repo run is slower.

## RAG Service

Located in `rag/` directory:
- FastAPI service
- Embeds score metadata using sentence-transformers
- Vector search via ChromaDB
- LLM reranking for smart search (DeepSeek)
- Called by Rails over the Kamal Docker network as `http://scorebase-rag:8001`

**Local development:**

```bash
cd rag
python -m venv venv && source venv/bin/activate
pip install -e .
python -m src.api.main  # Runs on :8001
```

**Production:** runs as a Kamal accessory `scorebase-rag` (image `ghcr.io/moguls753/scorebase-rag:latest`, built from `rag/Dockerfile`). The image bakes the `BAAI/bge-m3` embedding model at build time so cold starts don't depend on HuggingFace. That costs 4.3 GB of the ~6.3 GB image because the hub serves the weights twice — `refs/main` resolves to a revision carrying `pytorch_model.bin`, and sentence-transformers separately pulls `model.safetensors` from another revision. **Do not prune the second one to save 2.1 GB** (measured 2026-08-11): it is re-downloaded on the first `encode()`, so the space returns in the container's writable layer on every restart and the cold start starts depending on HuggingFace after all. Both Rails and the RAG container run as UID 1000 to share `scorebase_storage` (SQLite) safely. ChromaDB persists in `scorebase_chroma` volume.

**Two requirements files:** `rag/requirements.txt` is the local-dev manifest (includes `music21` for the extractor). `rag/requirements-prod.txt` is the slim manifest used by the Docker image (no music21; pinned `torch==2.x.x+cpu`).

## Smart Search / RAG Production Ops

**First-time / bulk indexing.**

```bash
bin/kamal rag-stats                                              # see what's pending
bin/kamal app exec --reuse -r web "bin/rails rag:mark_ready"
bin/kamal app exec --reuse -r web "bin/rails rag:generate LIMIT=1000"
bin/kamal rag-index                                              # one batch (5000 rows)
# repeat rag-index until rag-stats shows Templated == 0
```

The indexer's resume logic (`get_indexed_score_ids` in `rag/src/pipeline/indexer.py`) skips already-indexed rows, so partial progress is safe to retry. If a batch OOMs the 3.4 GB accessory cgroup, drop the alias's batch size from 5000 to 2000 in `config/deploy.yml`.

**Pruning deleted scores.** Every indexer run first reconciles ChromaDB against the live catalogue — vectors whose score was soft-deleted or purged are dropped (keep-set diff, `rag/src/pipeline/prune_deleted.py`). Run `bin/kamal rag-prune` (preview: `bin/kamal rag-prune-check`) to reconcile without indexing — e.g. right after a bulk delete. Both are safe to run while the RAG service is live; Chroma tolerates the concurrent reader.

**Rebuilding the RAG image.**

```bash
cd rag
docker build --platform linux/amd64 -t ghcr.io/moguls753/scorebase-rag:latest .
docker push ghcr.io/moguls753/scorebase-rag:latest
bin/kamal accessory reboot rag
```

**Secrets.** `DEEPSEEK_API_KEY` is sourced in `.kamal/secrets` from `bin/rails credentials:fetch deepseek.api_key`. Rails itself reads the same key from credentials directly (`Rails.application.credentials.dig(:deepseek, :api_key)`), so the env var is only set on the RAG accessory.

**ChromaDB concurrency.** The FastAPI process holds a Chroma reader open while the indexer process opens its own writer against the same `/data/chroma` volume. ChromaDB ≥ 0.4 uses SQLite/WAL for metadata and tolerates this in practice, but lock contention can surface as transient `/smart-search` 503s during heavy indexing — acceptable for a manually-run, infrequent operation. Fallback if it becomes disruptive: `bin/kamal accessory stop rag` before each batch, run the indexer in a transient container, `bin/kamal accessory boot rag` after.

## Search Console (`tools/gsc.rb`)

Reads Google Search Console. Deliberately **not** a Rails integration — stdlib only, no gems, nothing in the bundle, never deployed. Run it locally.

```bash
ruby tools/gsc.rb sites                                        # properties the service account can see
ruby tools/gsc.rb sitemaps                                     # fetched-at, errors, submitted vs indexed
ruby tools/gsc.rb inspect https://scorebase.org/scores/313510  # index status of one URL (2000/day)
ruby tools/gsc.rb query --dimensions page --days 90 --table
ruby tools/gsc.rb query --dimensions page,query --filter "page~~/scores/"
```

`query` prints JSON on stdout (pipe it into `bin/rails runner` to join against `scores`), or a summary with `--table`. Dimensions: `date query page country device searchAppearance`. Filter operators: `~~` contains, `==` equals, `!~` not-contains, `!=` not-equals, `=@` regex, `!@` not-regex. Pagination is automatic past the API's 25,000-row cap.

**Auth.** Service account `gsc-reader@scorebase-503011.iam.gserviceaccount.com`, key at `~/.config/scorebase/gsc-key.json` (override with `GSC_KEY`, exported from `~/.config/zsh/.zsh_secrets`). The key is **never** committed. A new service account also has to be added under *Search Console → Settings → Users and permissions* — with a valid key it otherwise authenticates fine and simply sees zero properties.

**Not available via the API:** the Index Coverage report (the "crawled – currently not indexed" buckets), Core Web Vitals, manual actions, the links report. Those are UI export only — download the Coverage ZIP and hand over the CSVs.

## Project Structure

```
app/                  # Rails app
rag/                  # Python RAG service
  src/
    api/              # FastAPI endpoints
    pipeline/         # Indexing and search
    llm/              # Result selection with explanations
config/               # Rails + Kamal config
```
