# ScoreBase

A search engine for public domain sheet music.

Aggregates scores from multiple sources:
- IMSLP (International Music Score Library Project)
- CPDL (Choral Public Domain Library)
- OpenScore Lieder
- OpenScore String Quartets

Normalizes composer names across sources, generates thumbnails, and provides filtering by key, time signature, genre, voicing, and more.

## Free vs Pro

**Free:** Browse, search, download 100k+ public domain scores.

**Pro ($2.99/mo):** AI-powered Smart Search that understands musical context—difficulty level, vocal ranges, duration, style, mood.

### Why a subscription?

Smart Search uses AI for every query—embedding your question, searching vectors, and ranking results with an LLM. These API calls cost real money. Your subscription covers the infrastructure while keeping the catalog free for everyone.

## Self-Hosting

This is fully open source. You can run your own instance:

```bash
bin/dev              # Start Rails
cd rag && python -m src.api.main  # Start RAG service
```

See `rag/` for the Python RAG service (FastAPI + ChromaDB + sentence-transformers).

## Links

- Live: [scorebase.org](https://scorebase.org)
