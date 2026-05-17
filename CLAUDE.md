# ScoreBase

Open source sheet music search engine. Deploys to scorebase.org.

## What Is This?

Sheet music search engine aggregating free public domain scores and commercial catalogs (Sheet Music Direct). Browse, search, download free PDFs or purchase commercial arrangements.

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
