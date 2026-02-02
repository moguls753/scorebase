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
