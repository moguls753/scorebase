# ScoreBase

Open source sheet music search engine. Deploys to scorebase.org.

## What Is This?

Sheet music search engine with AI-powered smart search. One search across free public domain scores (100k+) and commercial catalogs (1M+ via Sheet Music Direct).

- **Free:** Browse, search, download free PDFs or purchase commercial arrangements
- **Pro (€2/mo):** Unlimited Smart Search, favorites, collections

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
