"""FastAPI server for RAG search.

Rails calls this API to perform semantic search.
"""

import logging

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from ..pipeline import search as search_module

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)

app = FastAPI(title="ScoreBase RAG API")


# Request/Response models
class SearchResult(BaseModel):
    score_id: int
    content: str | None  # LLM-generated description
    similarity: float | None


class SearchResponse(BaseModel):
    query: str
    results: list[SearchResult]


# Endpoints
@app.get("/")
def health():
    """Health check."""
    return {"status": "ok", "service": "scorebase-rag"}


@app.get("/search")
def search(q: str, top_k: int = 10) -> SearchResponse:
    """Search for scores.

    Args:
        q: Search query (e.g., "easy Bach for piano")
        top_k: Number of results to return

    Returns:
        Matching scores with similarity scores
    """
    try:
        results = search_module.search(q, top_k=top_k)
    except Exception as e:
        logger.error(f"Search failed: {e}")
        raise HTTPException(
            status_code=503,
            detail="Search index not available. Run indexer first."
        )

    return SearchResponse(
        query=q,
        results=[
            SearchResult(
                score_id=r["score_id"],
                content=r["content"],
                similarity=r["similarity"],
            )
            for r in results
        ]
    )


def main():
    """Run the server."""
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)


if __name__ == "__main__":
    main()
