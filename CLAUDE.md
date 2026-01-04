# ScoreBase

Open source sheet music catalog. Deploys to scorebase.org.

## What Is This?

Sheet music catalog (100k+ public domain scores) with AI-powered smart search.

- **Free:** Browse, basic search, download
- **Pro (€2.99/mo):** Natural language RAG search, favorites, collections

## Tech Stack

- Rails 8
- SQLite (scores) + Postgres (users, vectors)
- Python/FastAPI RAG service
- ChromaDB + sentence-transformers for embeddings
- Stripe for billing
- Kamal for deployment
- Cloudflare CDN

## Development

```bash
bin/dev              # Start Rails
bin/rails test       # Run tests
bin/kamal deploy     # Deploy to production
```

## RAG Service

Located in `rag/` directory:
- FastAPI service
- Embeds score metadata using sentence-transformers
- Vector search via ChromaDB
- LLM reranking via Groq (Llama 3.3 70B)
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
