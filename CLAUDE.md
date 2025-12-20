 # ScoreBase Pro

 Private repo. Deploys to scorebase.org.

 ## What Is This?

 Sheet music catalog (300k+ public domain scores) with AI-powered smart search.

 - **Free:** Browse, basic search, download
 - **Pro ($2.99/mo):** Natural language RAG search, favorites, collections

 ## Architecture

 ```
 scorebase-pro (this repo)  →  deployed to scorebase.org
 scorebase (public repo)    →  portfolio showcase only (manual sync)
 ```

 One app. Pro features behind subscription. See `docs/pro-architecture.md`.

 ## Tech Stack

 - Rails 8
 - SQLite (scores) + Postgres (users, vectors)
 - Python/FastAPI RAG service
 - pgvector for embeddings
 - Stripe for billing
 - Kamal for deployment
 - Cloudflare CDN

 ## Key Docs

 - `docs/pro-architecture.md` — architecture decisions
 - `docs/scorebase-pro-product.md` — product spec, target users, example queries

 ## Development

 ```bash
 bin/dev              # Start Rails
 bin/rails test       # Run tests
 bin/kamal deploy     # Deploy to production
 ```

 ## RAG Service (TODO)

 Located in `rag/` directory:
 - FastAPI service
 - Embeds score metadata
 - Handles natural language queries
 - Called by Rails for pro users
