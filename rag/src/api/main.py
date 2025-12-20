"""FastAPI server for RAG search.

Rails calls this API to perform semantic search.
"""

from fastapi import FastAPI
from pydantic import BaseModel

from ..pipeline import search as search_module


app = FastAPI(title="ScoreBase RAG API")


# Request/Response models
class SearchResult(BaseModel):
    score_id: int
    title: str | None
    composer: str | None
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
    results = search_module.search(q, top_k=top_k)

    return SearchResponse(
        query=q,
        results=[
            SearchResult(
                score_id=r["score_id"],
                title=r["title"],
                composer=r["composer"],
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
