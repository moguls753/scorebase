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
bin/rspec            # Run tests
bin/kamal deploy     # Deploy to production
```

## Deployment Topology (Kamal)

**Single host (`46.224.124.123`), two roles** — both running on the same machine:

| Role | Memory | Command | Purpose |
|---|---|---|---|
| `web` | 1.5 GB | Puma (default) | Rails web server |
| `job` | 2 GB | `bin/jobs` | Solid Queue worker (music21 extraction needs the headroom) |

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

## Testing

- Use RSpec for all tests
- Keep tests small and simple
- Focus on behavior, not implementation details

## RAG Service

Located in `rag/` directory:
- FastAPI service
- Embeds score metadata using sentence-transformers
- Vector search via ChromaDB
- LLM reranking for smart search
- Called by Rails for smart search

```bash
cd rag
python -m venv venv && source venv/bin/activate
pip install -e .
python -m src.api.main  # Runs on :8001
```

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
