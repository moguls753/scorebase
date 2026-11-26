"""FastAPI server for RAG search.

Rails calls this API to perform semantic search.
"""

import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from ..pipeline import SearchBusy

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app):
    # Do not accept traffic with missing weights, an incomplete mount, or an unreadable catalogue.
    if path := os.environ.get("MLATEON_INDEX_PATH"):
        from ..pipeline.mlateon import warm_up
        warm_up(path)
    yield


app = FastAPI(title="ScoreBase RAG API", lifespan=lifespan)


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


class PreviousRecommendation(BaseModel):
    score_id: int
    title: str = Field(..., max_length=500)
    explanation: str = Field(..., max_length=500)
    rank: int | None = None


class SmartRefineRequest(BaseModel):
    original_query: str = Field(..., min_length=1, max_length=500)
    refinement: str = Field(..., min_length=1, max_length=300)
    previous_summary: str = Field(..., min_length=1, max_length=1000)
    previous_recommendations: list[PreviousRecommendation] = Field(..., min_length=1, max_length=5)


def search_error(exc: Exception) -> HTTPException:
    if isinstance(exc, SearchBusy):
        return HTTPException(status_code=503, detail="Search is busy. Try again shortly.", headers={"Retry-After": "2"})
    logger.exception("Search failed")
    return HTTPException(status_code=503, detail="Search temporarily unavailable.")


# Endpoints
@app.get("/")
def health():
    """Health check."""
    return {"status": "ok", "service": "scorebase-rag"}


@app.get("/search")
def search(q: str, top_k: int = Query(10, ge=1, le=1000)) -> SearchResponse:
    """Basic vector search for scores.

    Args:
        q: Search query (e.g., "easy Bach for piano")
        top_k: Number of results to return

    Returns:
        Matching scores with similarity scores
    """
    # Lazy import: keeps haystack / ML deps off the FastAPI app's import path so endpoint tests don't need them.
    from ..pipeline import search as search_module
    try:
        results = search_module.search(q, top_k=top_k)
    except Exception as e:
        raise search_error(e) from e

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
def smart_search(q: str, top_k: int | None = Query(None, ge=1)) -> SmartSearchResponse:
    """LLM-powered smart search with recommendations and explanations.

    This is the Pro feature endpoint. Returns 3 best matches with
    conversational explanations of why each piece fits the query.

    Args:
        q: Natural language query (e.g., "I need something for my piano student")
        top_k: Candidate limit; defaults to 30 for mLateOn or 15 for Chroma.

    Returns:
        3 recommendations with explanations and a summary
    """
    from ..llm.factory import required_api_key_env_var
    key_var = required_api_key_env_var()
    if key_var and not os.environ.get(key_var):
        raise HTTPException(
            status_code=503,
            detail=f"{key_var} not configured for smart search."
        )

    # Lazy import: keeps haystack / ML deps off the FastAPI app's import path so endpoint tests don't need them.
    from ..pipeline import search as search_module
    try:
        result = search_module.smart_search(q, top_k=top_k)
    except Exception as e:
        raise search_error(e) from e

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


@app.post("/smart-refine")
def smart_refine(req: SmartRefineRequest) -> SmartSearchResponse:
    """LLM-powered refinement: takes a previous query + answer + correction, returns a new ranked list.

    Same response shape as /smart-search.
    """
    from ..llm.factory import required_api_key_env_var
    key_var = required_api_key_env_var()
    if key_var and not os.environ.get(key_var):
        raise HTTPException(
            status_code=503,
            detail=f"{key_var} not configured for refinement."
        )

    # Lazy import: keeps haystack / ML deps off the FastAPI app's import path so endpoint tests don't need them.
    from ..pipeline import search as search_module
    try:
        result = search_module.smart_refine(
            original_query=req.original_query,
            refinement=req.refinement,
            previous_summary=req.previous_summary,
            previous_recommendations=[r.model_dump() for r in req.previous_recommendations],
        )
    except Exception as e:
        raise search_error(e) from e

    return SmartSearchResponse(
        query=f"{req.original_query} + {req.refinement}",
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
