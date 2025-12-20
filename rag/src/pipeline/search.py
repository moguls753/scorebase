"""Search pipeline using Haystack."""

from haystack import Pipeline
from haystack.components.embedders import SentenceTransformersTextEmbedder
from haystack_integrations.document_stores.chroma import ChromaDocumentStore
from haystack_integrations.components.retrievers.chroma import ChromaQueryRetriever

from .. import config

# Cache the pipeline to avoid reloading on every search
_pipeline = None


def get_pipeline() -> Pipeline:
    """Get or create search pipeline (cached)."""
    global _pipeline

    if _pipeline is not None:
        return _pipeline

    # Connect to ChromaDB
    document_store = ChromaDocumentStore(persist_path=str(config.CHROMA_PATH))

    # Build pipeline
    pipeline = Pipeline()

    # Text -> Embedding
    pipeline.add_component(
        "embedder",
        SentenceTransformersTextEmbedder(model=config.EMBEDDING_MODEL)
    )

    # Embedding -> Similar documents
    pipeline.add_component(
        "retriever",
        ChromaQueryRetriever(document_store=document_store, top_k=config.DEFAULT_TOP_K)
    )

    # Connect components
    pipeline.connect("embedder.embedding", "retriever.query_embedding")

    _pipeline = pipeline
    return pipeline


def search(query: str, top_k: int = 10) -> list[dict]:
    """Search for scores matching query.

    Args:
        query: Natural language search (e.g., "easy Bach for piano")
        top_k: Number of results

    Returns:
        List of results with score_id, title, composer, similarity
    """
    pipeline = get_pipeline()

    result = pipeline.run({
        "embedder": {"text": query},
        "retriever": {"top_k": top_k}
    })

    documents = result["retriever"]["documents"]

    return [
        {
            "score_id": doc.meta.get("score_id"),
            "title": doc.meta.get("title"),
            "composer": doc.meta.get("composer"),
            "content": doc.content,
            "similarity": doc.score,
        }
        for doc in documents
    ]


def main():
    """CLI entry point - test search."""
    import sys
    query = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "easy Bach for piano"

    print(f"Searching: '{query}'\n")

    results = search(query, top_k=5)

    for i, r in enumerate(results, 1):
        print(f"{i}. {r['title']}")
        print(f"   Composer: {r['composer']}")
        print(f"   Similarity: {r['similarity']:.3f}")
        print()


if __name__ == "__main__":
    main()
