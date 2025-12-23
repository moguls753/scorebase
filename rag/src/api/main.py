"""FastAPI server for RAG search.

Rails calls this API to perform semantic search.
"""

import logging
import os

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


class Recommendation(BaseModel):
    score_id: int
    title: str
    explanation: str
    rank: int


class SmartSearchResponse(BaseModel):
    query: str
    recommendations: list[Recommendation]
    summary: str
    success: bool


# Endpoints
@app.get("/")
def health():
    """Health check."""
    return {"status": "ok", "service": "scorebase-rag"}


@app.get("/search")
def search(q: str, top_k: int = 10) -> SearchResponse:
    """Basic vector search for scores.

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


@app.get("/smart-search")
def smart_search(q: str, top_k: int = 15) -> SmartSearchResponse:
    """LLM-powered smart search with recommendations and explanations.

    This is the Pro feature endpoint. Returns 3 best matches with
    conversational explanations of why each piece fits the query.

    Args:
        q: Natural language query (e.g., "I need something for my piano student")
        top_k: Number of candidates for LLM to consider (default 15)

    Returns:
        3 recommendations with explanations and a summary
    """
    if not os.environ.get("GROQ_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="GROQ_API_KEY not configured for smart search."
        )

    try:
        result = search_module.smart_search(q, top_k=top_k)
    except Exception as e:
        logger.error(f"Smart search failed: {e}")
        raise HTTPException(
            status_code=503,
            detail="Search failed. Check index and API key."
        )

    return SmartSearchResponse(
        query=q,
        recommendations=[
            Recommendation(
                score_id=r["score_id"],
                title=r["title"],
                explanation=r["explanation"],
                rank=r["rank"],
            )
            for r in result["recommendations"]
        ],
        summary=result["summary"],
        success=result["success"],
    )


def main():
    """Run the server."""
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)


if __name__ == "__main__":
    main()
