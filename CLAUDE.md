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

**Sitemap (commercial pages).** `config/sitemap.rb` lists SMD group representatives (`Score.active.smd_group_representatives`, ~7.3k × 2 locales) via a live query, so the weekly `SitemapRefreshJob` auto-includes newly imported/updated reps. Two operational notes: (1) **Edge caching of `public/` is controlled in the app, not at Cloudflare.** `/sitemap.xml.gz` is served by Rails' `ActionDispatch::Static`, so `config.public_file_server.headers` sets the TTL Cloudflare obeys. It is deliberately **1 week, not the Rails-default 1 year** — `public/` also holds non-digest-stamped files (sitemap, `robots.txt`, `og-image.png`), and the year-long default pinned an 8-day-stale sitemap at the edge, so Google indexed a version missing all 14.5k SMD rep URLs while the origin was correct. Diagnose this class of bug by comparing origin vs edge: `curl -sI --resolve scorebase.org:443:46.224.124.123 https://scorebase.org/sitemap.xml.gz` against a plain `curl -sI` (check `age` / `cf-cache-status`). No CF Cache Rule is needed; a one-time dashboard purge is only required to flush a copy cached under an old long-TTL header (no CF API token in the repo, R2 only, so purges are manual). (2) The sitemap is a single file; total is ~39k of the 50,000-URL limit (a sitemaps.org protocol cap per *file*, not a ScoreBase choice — it cannot be raised). Crossing it makes sitemap_generator switch to index mode and emit child files at `/sitemaps/sitemapN.xml.gz`. **That is now handled**: `bin/docker-entrypoint` symlinks both `public/sitemap.xml.gz` and the `public/sitemaps` directory, so index mode degrades gracefully instead of silently 404-ing every child. Verified end-to-end (child file serves 200 `application/x-gzip`; path traversal through the link still 404s).

**SQLite dump gotcha:** `db:migrate` regenerates `db/structure.sql` via `.schema`, which emits the FTS5 *shadow* tables (`*_fts_data/_idx/_docsize/_config`). Those are auto-created by `CREATE VIRTUAL TABLE` — leaving them in the dump breaks `db:test:prepare`. `structure.sql` is hand-maintained: after a migration, restore the committed version and add only your new objects (Rails can't filter shadow tables on SQLite; `SchemaDumper.ignore_tables` doesn't reach them).

**Ensemble hubs (buyer-query landing pages).** The `smd_category`-keyed ensemble hubs ("Concert Band Sheet Music", "SATB Choir Sheet Music") use a **CURATED** `HubDataBuilder::ENSEMBLE_CATEGORIES` allowlist — `smd_category` is a mixed taxonomy (most values are formats like "Piano Solo"), so it is never auto-derived. New scores in an existing allowlisted category auto-appear via the daily `HubCacheWarmJob`, but a genuinely new `smd_category` requires a one-line edit to the constant.

**Cross-links (free → SMD "Professional Editions"):** `score_smd_matches` is derived data (`BackfillSmdMatchesJob`, title+composer-surname matching via `SmdMatchFinder`). **After any import or bulk title/composer rewrite**, refresh it: `bin/kamal app exec --reuse -r web "bin/rails scores:backfill_smd_matches"` — the Sunday-5am recurring run is only a safety net. Bad match spotted in prod? Set `suppressed = true` on its row (console one-liner); the converge preserves it forever. Preview matches without writing: `DRY_RUN=1 bin/rails scores:backfill_smd_matches`.

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
bin/kamal deploy     # Deploy to production
```

## Deployment Topology (Kamal)

**Single Hetzner host (`46.224.124.123`)** — 4 vCPU, 8 GB RAM, 40 GB disk (~€16.65/month). Two Rails roles + one RAG accessory all share this host:

| Container | Memory | Command | Purpose |
|---|---|---|---|
| `web` | 1 GB | Puma (default) | Rails web server (1 worker × 3 threads) |
| `job` | 1 GB | `bin/jobs` | Solid Queue worker |
| `scorebase-rag` accessory | 1.5 GB | `uvicorn src.api.main:app` | Python/FastAPI RAG service on :8001 |

**Headroom budget.** Allocated containers consume `1 + 1 + 1.5 = 3.5 GB`. Remaining ~4.5 GB covers the OS / Docker daemon / Kamal proxy / cloudflare-bypass accessory and leaves room to grow individual containers if needed (e.g. bumping `scorebase-rag` to 3 GB for a heavier embedding model like bge-m3). Earlier 4 GB-host constraints — single Puma worker required, `job` capped at 1 GB — no longer bind; revisit those numbers when the workload demands it rather than treating them as fixed.

**Important consequence:** `bin/kamal app exec --reuse "<cmd>"` (no role flag) runs the command on **both** containers. For read-only dry-runs that's harmless duplication. For mutations, migrations, cleanup tasks, or anything one-shot, **always scope to a single role**:

```bash
bin/kamal app exec --reuse -r web "bin/rails <task>"
```

Use `-r web` for one-off rake tasks (cleanups, dry-runs, sitemap refreshes). Use `-r job` only when the task itself touches background-job state. Existing aliases in `config/deploy.yml` already follow this pattern — `sitemap` is the canonical example:

```yaml
sitemap: app exec --reuse -r web "bin/rails sitemap:refresh:no_ping"
```

Copy that shape when adding new aliases for recurring operations.

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
bundle audit              # gem CVE check
```

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

**Production:** runs as a Kamal accessory `scorebase-rag` (image `ghcr.io/moguls753/scorebase-rag:latest`, built from `rag/Dockerfile`). The image bakes the `paraphrase-multilingual-MiniLM-L12-v2` embedding model at build time so cold starts don't depend on HuggingFace. Both Rails and the RAG container run as UID 1000 to share `scorebase_storage` (SQLite) safely. ChromaDB persists in `scorebase_chroma` volume.

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

The indexer's resume logic (`get_indexed_score_ids` in `rag/src/pipeline/indexer.py`) skips already-indexed rows, so partial progress is safe to retry. If a batch OOMs the 1.5 GB accessory cgroup, drop the alias's batch size from 5000 to 2000 in `config/deploy.yml`.

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
