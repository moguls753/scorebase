# ScoreBase Pro Architecture

## Overview

One private app (deployed), one public repo (portfolio).

```
scorebase-pro/    (private)  →  scorebase.org (deployed)
scorebase/        (public)   →  GitHub portfolio only
```

## Why This Approach?

1. **One app to run** — single deploy, single logs, single test suite
2. **Portfolio piece** — public repo showcases clean code for resume
3. **No accidents** — pro code never touches public repo
4. **Simple ops** — no sync complexity, no merge conflicts

## What's Where

| Component | scorebase-pro (private) | scorebase (public) |
|-----------|:-----------------------:|:------------------:|
| Score catalog | ✓ | ✓ |
| Basic search | ✓ | ✓ |
| User accounts | ✓ | |
| Favorites | ✓ | |
| RAG smart search | ✓ | |
| Stripe billing | ✓ | |

## The Product: RAG Smart Search

Natural language queries for musicians:

- "Christmas piece for piano student, 2 years experience"
- "Choir piece for chamber music, soprano not above A4"
- "Easy Bach for beginner violin"

This is the paid feature. The RAG service (embeddings, prompts, search logic) is the IP.

## Pro Repo Structure

```
scorebase-pro/
├── app/
│   ├── models/
│   │   ├── score.rb
│   │   ├── user.rb           # pro
│   │   ├── favorite.rb       # pro
│   │   └── subscription.rb   # pro
│   └── controllers/
├── rag/                       # Python service (the secret sauce)
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py               # FastAPI
│   ├── embeddings.py
│   └── search.py
└── config/deploy.yml         # Kamal config
```

## Portfolio Sync (Manual)

Update public repo occasionally when you ship something impressive:

```bash
# Copy portfolio-worthy code
cp -r scorebase-pro/app/models/score.rb scorebase/app/models/
cp -r scorebase-pro/app/controllers/scores_controller.rb scorebase/

cd scorebase
git add .
git commit -m "Update catalog features"
git push
```

No git remotes, no branches, no cherry-picking. Just copy files.

## User Flow

```
scorebase.org
├── Browse, search, download (free, basic Postgres search)
├── "Go Pro" → login → subscribe
└── Pro users get RAG-powered smart search
```

One domain. One app. Pro features behind subscription check.
